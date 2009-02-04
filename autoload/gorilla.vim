"-
" Copyright 2009 (c) Meikel Brandmeyer.
" All rights reserved.
"
" Permission is hereby granted, free of charge, to any person obtaining a copy
" of this software and associated documentation files (the "Software"), to deal
" in the Software without restriction, including without limitation the rights
" to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
" copies of the Software, and to permit persons to whom the Software is
" furnished to do so, subject to the following conditions:
"
" The above copyright notice and this permission notice shall be included in
" all copies or substantial portions of the Software.
"
" THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
" IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
" FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
" AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
" LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
" OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
" THE SOFTWARE.

let s:save_cpo = &cpo
set cpo&vim

" Helpers
function! gorilla#ExtractSexpr(toplevel)
	let closure = { "flag" : (a:toplevel ? "r" : "") }

	function closure.f() dict
		if searchpairpos('(', '', ')', 'bW' . self.flag,
					\ 'vimclojure#SynIdName() !~ "clojureParen\\d"') != [0, 0]
			return vimclojure#Yank('l', 'normal "ly%')
		end
		return ""
	endfunction

	return vimclojure#WithSavedPosition(closure)
endfunction

" Key mappings and Plugs
function! gorilla#MakePlug(mode, plug, f)
	execute a:mode . "noremap <Plug>ClojureChimp" . a:plug
				\ . " :call " . a:f . "<CR>"
endfunction

function! gorilla#MapPlug(mode, keys, plug)
	if !hasmapto("<Plug>ClojureChimp" . a:plug)
		execute a:mode . "map <buffer> <unique> <silent> <LocalLeader>" . a:keys
					\ . " <Plug>ClojureChimp" . a:plug
	endif
endfunction

" A Buffer...
let gorilla#Buffer = {}

function! gorilla#Buffer.goHere() dict
	execute "buffer! " . self._buffer
endfunction

function! gorilla#Buffer.resize() dict
	call self.goHere()
	let size = line("$")
	if size < 3
		let size = 3
	endif
	execute "resize " . size
endfunction

function! gorilla#Buffer.showText(text) dict
	call self.goHere()
	call append(line("$"), split(a:text, '\n'))
endfunction

function! gorilla#Buffer.close() dict
	execute "bdelete! " . self._buffer
endfunction

" The transient buffer, used to display results.
let gorilla#TransientBuffer = copy(gorilla#Buffer)

function! gorilla#TransientBuffer.New() dict
	let instance = copy(self)

	new
	let instance._buffer = bufnr("%")

	setlocal noswapfile
	setlocal buftype=nofile
	setlocal bufhidden=delete

	nnoremap <buffer> <silent> q :hide<CR>

	call append(0, "; Press q to close this buffer!")

	return instance
endfunction

" Nails
if !exists("gorilla#NailgunClient")
	let gorilla#NailgunClient = "ng"
endif

function! gorilla#ExecuteNail(nail, ...)
	let cmd = join([g:gorilla#NailgunClient,
				\ "de.kotka.gorilla.nails." . a:nail] + a:000, " ")
	let result = system(cmd)
	if v:shell_error
		throw "Couldn't execute Nail! " . cmd
	endif
	return substitute(result, '\n$', '', '')
endfunction

function! gorilla#FilterNail(nail, rngStart, rngEnd, ...)
	let cmd = join([a:rngStart . "," . a:rngEnd . "!",
				\ g:gorilla#NailgunClient,
				\ "de.kotka.gorilla.nails." . a:nail] + a:000, " ")

	silent execute cmd
endfunction

function! gorilla#DocLookup(word)
	let docs = gorilla#ExecuteNail("DocLookup",
				\ "--namespace", b:gorilla_namespace,
				\ "--", a:word)
	let transientBuffer = g:gorilla#TransientBuffer.New()
	call transientBuffer.showText(docs)
endfunction

let s:DefaultJavadocPaths = {
			\ "java" : "http://java.sun.com/javase/6/docs/api/",
			\ "org/apache/commons/beanutils" : "http://commons.apache.org/beanutils/api/",
			\ "org/apache/commons/chain" : "http://commons.apache.org/chain/api-release/",
			\ "org/apache/commons/cli" : "http://commons.apache.org/cli/api-release/",
			\ "org/apache/commons/codec" : "http://commons.apache.org/codec/api-release/",
			\ "org/apache/commons/collections" : "http://commons.apache.org/collections/api-release/",
			\ "org/apache/commons/logging" : "http://commons.apache.org/logging/apidocs/",
			\ "org/apache/commons/mail" : "http://commons.apache.org/email/api-release/",
			\ "org/apache/commons/io" : "http://commons.apache.org/io/api-release/"
			\ }

if !exists("gorilla#JavadocPathMap")
	let gorilla#JavadocPathMap = {}
endif

for k in keys(s:DefaultJavadocPaths)
	if !has_key(gorilla#JavadocPathMap, k)
		let gorilla#JavadocPathMap[k] = s:DefaultJavadocPaths[k]
	endif
endfor

if !exists("gorilla#Browser")
	if has("win32") || has("win64")
		let gorilla#Browser = "start"
	elseif has("mac")
		let gorilla#Browser = "open"
	else
		let gorilla#Browser = "firefox -new-window"
	endif
endif

function! gorilla#JavadocLookup(word)
	let path = gorilla#ExecuteNail("JavadocPath",
				\ "--namespace", b:gorilla_namespace,
				\ "--", a:word)

	let match = ""
	for pattern in keys(g:gorilla#JavadocPathMap)
		if path =~ "^" . pattern && len(match) < len(pattern)
			let match = pattern
		endif
	endfor

	if match == ""
		throw "No matching Javadoc URL found for " . path
	endif

	let url = g:gorilla#JavadocPathMap[match] . path
	call system(join([g:gorilla#Browser, url], " "))
endfunction

" Evaluators
function! gorilla#MacroExpand(firstOnly)
	let sexp = gorilla#ExtractSexpr(0)
	let ns = b:gorilla_namespace

	let resultBuffer = g:gorilla#TransientBuffer.New()
	setfiletype clojure

	let firstLine = line("$")
	call resultBuffer.showText(sexp)
	let lastLine = line("$")

	let cmd = ["MacroExpand", firstLine, lastLine, "-n", ns]
	if a:firstOnly
		let cmd = cmd + [ "-o" ]
	endif

	call call(function("gorilla#FilterNail"), cmd)
endfunction

" The Repl
let gorilla#Repl = copy(gorilla#Buffer)

let gorilla#Repl._prompt = "Gorilla=>"
let gorilla#Repl._history = []
let gorilla#Repl._historyDepth = 0
let gorilla#Repl._replCommands = [ ",close" ]

function! gorilla#Repl.New() dict
	let instance = copy(self)

	new
	setlocal buftype=nofile
	setlocal noswapfile

	inoremap <buffer> <silent> <CR>     <Esc>:call b:gorilla_repl.enterHook()<CR>
	inoremap <buffer> <silent> <C-Up>   <C-O>:call b:gorilla_repl.upHistory()<CR>
	inoremap <buffer> <silent> <C-Down> <C-O>:call b:gorilla_repl.downHistory()<CR>

	call append(line("$"), ["Clojure", self._prompt . " "])

	let instance._id = gorilla#ExecuteNail("Repl", "-s")
	let instance._buffer = bufnr("%")

	let b:gorilla_repl = instance

	setfiletype clojurerepl

	normal G
	startinsert!
endfunction

function! gorilla#Repl.isReplCommand(cmd) dict
	for candidate in self._replCommands
		if candidate == a:cmd
			return 1
		endif
	endfor
	return 0
endfunction

function! gorilla#Repl.doReplCommand(cmd) dict
	if a:cmd == ",close"
		call gorilla#ExecuteNail("Repl", "-S", "-i", self._id)
		call self.close()
		stopinsert
	endif
endfunction

function! gorilla#Repl.getCommand() dict
	let ln = line("$")

	while getline(ln) !~ "^" . self._prompt
		let ln = ln - 1
	endwhile

	let cmd = vimclojure#Yank("l", ln . "," . line("$") . "yank l")

	let cmd = substitute(cmd, "^" . self._prompt . "\\s*", "", "")
	let cmd = substitute(cmd, "\n$", "", "")
	return cmd
endfunction

function! gorilla#Repl.enterHook() dict
	let cmd = self.getCommand()

	if self.isReplCommand(cmd)
		call self.doReplCommand(cmd)
		return
	endif

	let rangeStart = line("$") + 1
	call self.showText(cmd)
	let rangeEnd = line("$")

	call gorilla#FilterNail("CheckSyntax", rangeStart, rangeEnd)
	let result = getline("$")
	if result == "false"
		normal G0Dix
		normal ==x
	else
		normal Gdd
		let rangeStart = line("$") + 1
		call self.showText(cmd)
		let rangeEnd = line("$")

		call gorilla#FilterNail("Repl", rangeStart, rangeEnd,
					\ "-r", "-i", self._id)

		let self._historyDepth = 0
		let self._history = [cmd] + self._history
		call self.showText(self._prompt . " ")
		normal G
	endif
	startinsert!
endfunction

function! gorilla#Repl.upHistory() dict
	let histLen = len(self._history)
	let histDepth = self._historyDepth

	if histLen > 0 && histLen > histDepth
		let cmd = self._history[histDepth]
		let self._historyDepth = histDepth + 1

		call self.deleteLast()

		call self.showText(self._prompt . " " . cmd)
	endif

	normal G$
endfunction

function! gorilla#Repl.downHistory() dict
	let histLen = len(self._history)
	let histDepth = self._historyDepth

	if histDepth > 0 && histLen > 0
		let self._historyDepth = histDepth - 1
		let cmd = self._history[self._historyDepth]

		call self.deleteLast()

		call self.showText(self._prompt . " " . cmd)
	elseif histDepth == 0
		call self.deleteLast()
		call self.showText(self._prompt . " ")
	endif

	normal G$
endfunction

function! gorilla#Repl.deleteLast() dict
	normal G

	while getline("$") !~ self._prompt
		normal dd
	endwhile

	normal dd
endfunction

" Epilog
let &cpo = s:save_cpo