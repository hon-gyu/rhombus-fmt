#lang racket/base
;; A Rhombus formatter that keeps aligned indentation.
;;
;; Usage: racket rhombus-fmt.rkt [-i] [--no-check] FILE ...
;;   Prints the formatted FILE, or with `-i` rewrites it in place.
;;   `--no-check` skips reading the result back, for debugging.
;;
;; Line breaks are kept. Within a line, whitespace between tokens is
;; normalized. Each line is then indented relative to the token that gives
;; it its meaning, using the new column of that token:
;;
;; - a group lines up with the first group of its sequence
;; - the first group of a block or bracket, when it starts a line, is
;;   indented 2 past the group that owns the block or bracket
;; - a continuation line keeps its offset from the start of its group
;; - a `|` lines up with the first `|` of its alternatives, and the first
;;   keeps its offset from its group
;; - a closer starting a line lines up with the line of its opener
;; - text lines of `@` notation move by as much as their `{`
;; - comment lines move by as much as the next line, and lines of a group
;;   commented out by `#//` by as much as the line before, as written
;;
;; The result must read to the same shrubbery as the input, strings
;; included, or the file is left alone and an error is reported.
(require racket/cmdline
         racket/list
         racket/port
         racket/string
         shrubbery/lex
         shrubbery/parse)

;; Tokens
;; ======

;; `start` and `end` are 0-based positions in the body
(struct tok (name start end) #:transparent)

(define (lex-body body)
  (define in (open-input-string body))
  (port-count-lines! in)
  (for/vector ([t (in-list (lex-all in (lambda args (error "not shrubbery notation"))))]
               #:unless (eq? (token-name t) 'EOF))
    (define v (token-value t))
    (define start (sub1 (syntax-position v)))
    (tok (token-name t) start (+ start (syntax-span v)))))

;; Index of the token containing `pos`, assuming tokens cover the body
(define (token-at toks pos)
  (let loop ([lo 0] [hi (vector-length toks)])
    (cond
      [(>= lo hi) #f]
      [else
       (define mid (quotient (+ lo hi) 2))
       (define t (vector-ref toks mid))
       (cond
         [(< pos (tok-start t)) (loop lo mid)]
         [(>= pos (tok-end t)) (loop (add1 mid) hi)]
         [else mid])])))

;; Maps each closer to its opener, and each `at-content` or `at-closer` to
;; the `at-opener` of its text
(define (match-brackets toks)
  (define opener-of (make-hasheqv))
  (for/fold ([stack '()]) ([t (in-vector toks)])
    (case (tok-name t)
      [(opener at-opener) (cons t stack)]
      [(closer at-closer)
       (cond
         [(pair? stack)
          (hash-set! opener-of (tok-start t) (tok-start (car stack)))
          (cdr stack)]
         [else stack])]
      [(at-content)
       (when (pair? stack)
         (hash-set! opener-of (tok-start t) (tok-start (car stack))))
       stack]
      [else stack]))
  opener-of)

;; Roles
;; =====

;; Maps the position of the first token of each term to how a line starting
;; with it is indented:
;;   (list 'zero)
;;   (list 'below pos)        ; 2 past the column of pos
;;   (list 'align pos)        ; the column of pos
;;   (list 'offset pos)       ; the old offset from pos, at its new column
(define (build-roles stx at-start)
  (define roles (make-hasheqv))
  ;; #f for parentheses implied by `@` notation
  (define (pos-of s) (and (syntax-position s) (sub1 (syntax-position s))))
  ;; the position of a term, counting a leading `@` as part of it
  (define (term-pos t)
    (define e (syntax-e t))
    (define p (pos-of (if (pair? e) (car e) t)))
    (and p (hash-ref at-start p p)))
  (define (first-term-pos g)
    (define ts (cdr (syntax->list g)))
    (and (pair? ts) (term-pos (car ts))))
  (define (tag t)
    (define e (syntax-e t))
    (and (pair? e) (syntax-e (car e))))
  (define (walk-seq groups first-role)
    (define first (and (pair? groups) (first-term-pos (car groups))))
    (for ([g (in-list groups)]
          [i (in-naturals)])
      (define p (first-term-pos g))
      (when p
        (hash-set! roles p (if (zero? i) first-role (list 'align first))))
      (walk-group g)))
  (define (walk-group g)
    (define ts (cdr (syntax->list g)))
    (define start (and (pair? ts) (term-pos (car ts))))
    (for ([t (in-list ts)]
          [j (in-naturals)])
      (case (tag t)
        [(alts)
         (define alts (cdr (syntax->list t)))
         (define first-bar (pos-of (car (syntax-e (car alts)))))
         (for ([a (in-list alts)]
               [k (in-naturals)])
           (define bar (pos-of (car (syntax-e a))))
           (hash-set! roles bar (if (zero? k) (list 'offset start) (list 'align first-bar)))
           (walk-seq (cdr (syntax->list a)) (list 'below bar)))]
        [else
         (when (and (positive? j) (term-pos t))
           (hash-set! roles (term-pos t) (list 'offset start)))
         (case (tag t)
           [(parens brackets braces quotes block)
            (walk-seq (cdr (syntax->list t)) (list 'below start))]
           [else (void)])])))
  (walk-seq (cdr (syntax->list stx)) (list 'zero))
  roles)

;; Formatting
;; ==========

(define (space-before? c) (memv c '(#\space #\tab)))

;; Whitespace to put between tokens `a` and `b` on one line, given the
;; original whitespace `gap`
(define (normalize-gap a b gap)
  (define an (tok-name a))
  (define bn (tok-name b))
  (cond
    [(memq bn '(comment)) gap]
    [(eq? an 'comma-operator) " "]
    [(string=? gap "") gap]
    [(memq bn '(closer comma-operator semicolon-operator)) ""]
    [(eq? an 'opener) ""]
    [else " "]))

(define (format-body body)
  (define toks (lex-body body))
  (define opener-of (match-brackets toks))
  ;; an `@` followed directly by its command starts the command's term
  (define at-start
    (for/hasheqv ([t (in-vector toks)]
                  [i (in-naturals)]
                  #:when (and (eq? (tok-name t) 'at)
                              (< (add1 i) (vector-length toks))))
      (values (tok-start (vector-ref toks (add1 i))) (tok-start t))))
  (define in (open-input-string body))
  (port-count-lines! in)
  (define roles (build-roles (parse-all in) at-start))

  (define lines (string-split body "\n" #:trim? #f))
  (define starts (for/fold ([acc '(0)] #:result (list->vector (reverse acc)))
                           ([l (in-list (drop-right lines 1))])
                   (cons (+ (car acc) (string-length l) 1) acc)))
  (define n (length lines))
  (define (line-of pos)
    (let loop ([lo 0] [hi n])
      (if (= (add1 lo) hi)
          lo
          (let ([mid (quotient (+ lo hi) 2)])
            (if (< pos (vector-ref starts mid)) (loop lo mid) (loop mid hi))))))
  (define (old-col pos) (- pos (vector-ref starts (line-of pos))))

  (define new-col (make-hasheqv))
  (define deltas (make-vector n #f))
  (define out (make-vector n ""))
  ;; comment lines, indented once the next line is known
  (define floating '())

;; The delta of line `i`, or of the closest line before it that has one
  (define (delta-at i)
    (cond
      [(< i 0) 0]
      [(vector-ref deltas i)]
      [else (delta-at (sub1 i))]))

  (define (col-of pos)
    (hash-ref new-col pos (lambda () (error 'rhombus-fmt "no column for position ~a" pos))))

  ;; Moves a line by `delta` without touching its content
  (define (shift-line! i delta)
    (define s (vector-ref starts i))
    (define text (list-ref lines i))
    (define indent (for/sum ([c (in-string text)] #:break (not (space-before? c))) 1))
    (define new-indent (max 0 (+ indent delta)))
    (vector-set! deltas i (- new-indent indent))
    (vector-set! out i (string-append (make-string new-indent #\space) (substring text indent)))
    (for ([t (in-vector toks)]
          #:when (and (<= s (tok-start t)) (< (tok-start t) (+ s (string-length text)))))
      (hash-set! new-col (tok-start t) (+ (old-col (tok-start t)) (- new-indent indent)))))

  ;; Respaces a line starting at token index `k` and indents it to `indent`
  (define (respace-line! i k indent)
    (define s (vector-ref starts i))
    (define e (+ s (string-length (list-ref lines i))))
    ;; pieces of the line in reverse, and its length in characters
    (define pieces (list (make-string indent #\space)))
    (define col indent)
    (define (emit! str)
      (set! pieces (cons str pieces))
      (set! col (+ col (string-length str))))
    (let loop ([k k] [prev #f] [gap ""])
      (when (< k (vector-length toks))
        (define t (vector-ref toks k))
        (when (< (tok-start t) e)
          (define text (substring body (tok-start t) (min e (tok-end t))))
          (cond
            [(eq? (tok-name t) 'whitespace)
             (loop (add1 k) prev (string-append gap (car (string-split text "\n" #:trim? #f))))]
            [else
             (when prev
               (emit! (normalize-gap prev t gap)))
             (hash-set! new-col (tok-start t) col)
             (emit! text)
             (loop (add1 k) t "")]))))
    (define old-indent (- (tok-start (vector-ref toks k)) s))
    (vector-set! deltas i (- indent old-indent))
    (vector-set! out i (apply string-append (reverse pieces))))

  (define (indent-for role first)
    (case (car role)
      [(zero) 0]
      [(below) (+ 2 (col-of (cadr role)))]
      [(align) (col-of (cadr role))]
      [(offset) (+ (col-of (cadr role)) (- (old-col first) (old-col (cadr role))))]))

  (for ([i (in-range n)])
    (define s (vector-ref starts i))
    (define text (list-ref lines i))
    (define f (for/first ([c (in-string text)]
                          [j (in-naturals)]
                          #:unless (space-before? c))
                (+ s j)))
    ;; the token holding the newline before this line
    (define before (and (positive? s) (vector-ref toks (token-at toks (sub1 s)))))
    (cond
      [(and before (eq? (tok-name before) 'at-content))
       ;; text of `@` notation
       (define opener (hash-ref opener-of (tok-start before)))
       (shift-line! i (delta-at (line-of opener)))]
      [(and before (eq? (tok-name before) 'comment))
       ;; inside a block comment
       (shift-line! i (delta-at (line-of (tok-start before))))]
      [(not f)
       (vector-set! deltas i 0)
       (vector-set! out i "")]
      [else
       (define k (token-at toks f))
       (define t (vector-ref toks k))
       (case (tok-name t)
         [(comment group-comment)
          (set! floating (cons i floating))]
         [(closer)
          (define opener-line (line-of (hash-ref opener-of f)))
          (define opener-indent
            (for/sum ([c (in-string (vector-ref out opener-line))] #:break (not (space-before? c))) 1))
          (respace-line! i k opener-indent)]
         [else
          (define first (if (eq? (tok-name t) 'at) (tok-start (vector-ref toks (add1 k))) f))
          (define role (hash-ref roles first #f))
          (cond
            [role (respace-line! i k (indent-for role f))]
            ;; inside a `#//` comment, which has no tree: move with the line
            ;; before, as written
            [else (shift-line! i (delta-at (sub1 i)))])])
       ;; comment lines move with the line after them
       (when (and (pair? floating) (not (memv i floating)))
         (for ([j (in-list floating)])
           (shift-line! j (vector-ref deltas i)))
         (set! floating '()))]))
  (for ([j (in-list floating)])
    (shift-line! j 0))

  (string-join (for/list ([l (in-vector out)]) (string-trim l #:left? #f)) "\n"))

;; Files
;; =====

(define (read-shrubbery body)
  (define in (open-input-string body))
  (port-count-lines! in)
  (format "~s" (syntax->datum (parse-all in))))

;; Returns the formatted text, or raises an error
(define check? (make-parameter #t))

(define (format-text text)
  (define m (regexp-match #rx"^#lang[^\n]*" text))
  (define lang (and m (car m)))
  (cond
    [(and lang (regexp-match? #rx"scribble" lang))
     ;; the module body is text
     text]
    [else
     ;; blank out the `#lang` line so positions stay the same
     (define body (if lang (substring text (string-length lang)) text))
     (define new-body (format-body body))
     (unless (or (not (check?)) (equal? (read-shrubbery body) (read-shrubbery new-body)))
       (error 'rhombus-fmt "formatting would change the meaning"))
     (string-append (or lang "") new-body)]))

(module+ main
  (define in-place? (make-parameter #f))
  (define files
    (command-line
     #:once-each
     [("-i") "Rewrite files in place" (in-place? #t)]
     [("--no-check") "Do not check that the meaning is unchanged" (check? #f)]
     #:args files
     files))
  (define failed? #f)
  (for ([f (in-list files)])
    (define text (call-with-input-file f port->string))
    (with-handlers ([exn:fail? (lambda (e)
                                 (set! failed? #t)
                                 (eprintf "~a: ~a\n" f (exn-message e)))])
      (define new (format-text text))
      (if (in-place?)
          (unless (equal? new text)
            (call-with-output-file f (lambda (o) (write-string new o)) #:exists 'truncate))
          (write-string new))))
  (when failed? (exit 1)))
