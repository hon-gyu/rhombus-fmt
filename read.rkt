#lang racket/base
;; Print the shrubbery parse of each file, strings included, for check.py.
;; Usage: racket read.rkt FILE ...
;; Prints one line per file: FILE, a tab, then the parse or `ERROR: message`.
(require racket/port
         racket/string
         shrubbery/parse)

(define (parse-file path)
  (define text (call-with-input-file path port->string))
  ;; blank out a `#lang` line so positions stay the same
  (define body (regexp-replace #rx"^#lang[^\n]*" text ""))
  (define in (open-input-string body))
  (port-count-lines! in)
  ;; a Scribble `#lang` reads the module body as text
  (define mode (if (regexp-match? #rx"^#lang[^\n]*scribble" text) 'text 'top))
  (with-handlers ([exn:fail? (lambda (e)
                               (format "ERROR: ~a" (car (string-split (exn-message e) "\n"))))])
    (format "~s" (syntax->datum (parse-all in #:mode mode)))))

(for ([path (in-vector (current-command-line-arguments))])
  (printf "~a\t~a\n" path (parse-file path)))
