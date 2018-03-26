;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;         Interactive Code         ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(defvar sep "§")

;;;;;;;;        Commands        ;;;;;;;;

;(defun cedille-mode-to-string (input)
;  "Sends an interactive request to the backend to parse INPUT and return the parsed expression as a string"
;  (interactive "MExpression: ")
;  (se-inf-interactive (concat "interactive" sep "to-string" sep input) (lambda (r oc) (message r)) :header "To-String-ing"))

(defun cedille-mode-normalize(&optional head)
  "Normalizes either the currently selected span or a prompted expression completely"
  (interactive)
  (if se-mode-selected
      (cedille-mode-normalize-span (se-mode-selected) head)
    (cedille-mode-normalize-prompt head)))

(defun cedille-mode-head-normalize
  (interactive)
  (cedille-mode-normalize t))

(defun cedille-mode-erase ()
  "Erases either the currently selected span or a prompted expression"
  (interactive)
  (if se-mode-selected
      (cedille-mode-erase-span (se-mode-selected))
    (call-interactively
     (lambda (input)
       (interactive "MErase: ")
       (cedille-mode-erase-send-prompt input)))))
  

;;;;;;;;        Span Code        ;;;;;;;;

(defun cedille-mode-normalize-span(span head)
  "Normalizes (or head-normalizes if HEAD is t) SPAN"
  (let ((lang-level (cedille-mode-normalize-get-ll span))
	(header (concat (if head "Head-n" "N") "ormalizing")))
    (if (and lang-level (or (string= lang-level "term")
			    (string= lang-level "type")
			    (string= lang-level "kind")))
	(se-inf-interactive
	 'cedille-mode-normalize-request-text
	 (cedille-mode-response-macro #'cedille-mode-normalize-erase-receive-response)
	 :span span
	 :header header
	 :extra (cons head nil) ; To make sure that extra is non-nil
	 :restore t)
      (message "Node must be a term, type, or kind"))))

(defun cedille-mode-erase-span (span)
  "Erases span"
  (let ((lang-level (cedille-mode-normalize-get-ll span)))
    (if (and lang-level (string= lang-level "term"))
	(se-inf-interactive
	 'cedille-mode-erase-request-text
	 (cedille-mode-response-macro #'cedille-mode-normalize-erase-receive-response)
	 :span span
	 :header "Erasing"
	 :restore t)
      (message "Node must be a term"))))

(defun cedille-mode-normalize-erase-receive-response (response span oc &optional extra)
  "Receives the text response from the backend and adds (symbol . response) to span."
  (when oc
    (add-hook 'se-inf-interactive-response-hook #'cedille-mode-normalize-inspect))
  (cons (if extra (if (car extra) 'head-normalized 'normalized) 'erased) response))

(defun cedille-mode-normalize-request-text(span extra &optional add-to-pos) ; add-to-pos is for beta-reduction
  "Gets the text to send to the backend as a request to normalize a span"
  (let* ((head (car extra))
	 (s (se-span-start span))
	 (e (se-span-end span)))
    (concat "interactive"
	    sep "normalize"
	    sep (buffer-substring s e)
	    sep (cedille-mode-normalize-get-ll span)
	    sep (number-to-string (+ s (or add-to-pos 0)))
	    sep (if head "tt" "ff")
	    sep (if add-to-pos "tt" "ff") ; do-erase, which coincides with add-to-pos
	    (cedille-mode-normalize-local-context-param span))))

(defun cedille-mode-erase-request-text(span)
  "Gets the text to send to the backend as a request to normalize a span"
  (let ((s (se-span-start span))
	(e (se-span-end span)))
    (cedille-mode-erase-request-text-h (buffer-substring s e) (cedille-mode-normalize-get-ll span) s (cedille-mode-normalize-local-context-param span))))

(defun cedille-mode-erase-request-text-h (str ll pos lc-str)
  (concat "interactive"
	  sep "erase"
	  sep str
	  sep ll
	  sep (number-to-string pos)
	  lc-str))

(defun cedille-mode-normalize-local-context-param(span)
  "Formats the local context into a string suitable to be sent to the backend"
  (let ((original-context (cedille-mode-span-context span)))
    (when original-context
      (cedille-mode-normalize-local-context-to-string (copy-tree original-context)))))

(defun cedille-mode-normalize-local-context-to-string(ctxt)
  "Converts CTXT into a string suitable to be sent to the backend"
  (let* ((terms (cedille-mode-normalize-shadow-filter (car ctxt)))
	 (types (cedille-mode-normalize-shadow-filter (cdr ctxt)))
	 (out "")
	 (split (lambda (item)
		  (let ((loc (cdr (assoc 'location item)))
			(del " - "))
		    (when loc
		      (let ((dash (string-match del loc)))
			(when dash
			  (cons (substring loc 0 dash) (substring loc (+ dash (length del)))))))))))
    (while terms
      (let* ((item (pop terms))
	     (loc (funcall split item))
	     (value (cdr (assoc 'value item)))
	     (bv (or (cdr (assoc 'bound-value item)) "")))
	(setq out (concat out sep "term" sep (car item) sep bv sep value sep (car loc) sep (cdr loc)))))
    (while types
      (let* ((item (pop types))
	     (loc (funcall split item))
	     (value (cdr (assoc 'value item)))
	     (bv (or (cdr (assoc 'bound-value item)) "")))
	(setq out (concat out sep "type" sep (car item) sep bv sep value sep (car loc) sep (cdr loc)))))
    out))

(defun cedille-mode-normalize-shadow-filter(lst)
  (let (shadowed-lst)
    (dolist (pair (reverse lst) shadowed-lst)
      (let* ((symbol (car pair)) (matches (lambda (thispair) (equal (car thispair) symbol))))
	(setq shadowed-lst (cons pair (remove-if matches shadowed-lst)))))
    shadowed-lst))

(defun cedille-mode-normalize-get-ll (term)
  "Returns the language level of TERM"
  (cdr (assoc 'language-level (se-term-data term))))

(defun cedille-mode-normalize-inspect ()
  "Updates the inspect buffer and opens it if it is closed"
  (remove-hook 'se-inf-interactive-response-hook #'cedille-mode-normalize-inspect)
  (when (not se-inf-interactive-running)
    (let ((buffer (cedille-mode-inspect-buffer)))
      (with-current-buffer buffer
	(display-buffer buffer))
      (cedille-mode-inspect))))




;;;;;;;;        Prompt Code        ;;;;;;;;

(defun cedille-mode-normalize-prompt (&optional head)
  "Prompts the user to input an expression to normalize/head-normalize"
  (let ((head-t (lambda (input)
		  (interactive "MHead-normalize: ")
		  (cedille-mode-normalize-send-prompt input t)))
	(head-nil (lambda (input)
		    (interactive "MNormalize: ")
		    (cedille-mode-normalize-send-prompt input nil))))
  (call-interactively (if head head-t head-nil))))

(defun cedille-mode-normalize-send-prompt (input head)
  "Sends the prompted normalize request to the backend"
  (se-inf-interactive
   (concat "interactive" sep "normalizePrompt" sep input sep (if head "tt" "ff"))
   (cedille-mode-response-macro #'cedille-mode-normalize-erase-receive-response-prompt)
   :extra (concat "Expression: " input "\n" (if head "Head-n" "N") "ormalized: ")
   :header "Normalizing"))

(defun cedille-mode-erase-send-prompt (input)
  (se-inf-interactive
   (concat "interactive" sep "erasePrompt" sep input)
   (cedille-mode-response-macro #'cedille-mode-normalize-erase-receive-response-prompt)
   :extra (concat "Expression: " input "\nErased: ")
   :header "Erasing"))

(defun cedille-mode-normalize-erase-receive-response-prompt(response oc extra s)
  "Receives the normalize text response (or error text) from the backend. Handler for when the user typed an expression into the prompt."
  (cedille-mode-scratch-insert-text (concat extra response)))

;;;;;;;;        Helpers        ;;;;;;;;

(defun cedille-mode-str-is-var (str)
  "Returns t if STR is a variable"
  (not (string-match " " str)))


(defun cedille-mode-response (fn response span oc extra)
  "Wrapper function that turns RESPONSE into a json, propertizes it, and passes it to FN along with OC and EXTRA"
  (let* ((json-array-type 'list)
         (json (json-read-from-string response))
         (ls (cdr (assoc 'value json)))
         (err (cdr (assoc 'error json)))
         (val (cadr ls))
         (ts (caddr ls))
         (str (cedille-mode-apply-tags val ts)))
    (if err
        (message err)
      (funcall fn str span oc extra))))

(defmacro cedille-mode-response-macro (fn)
  `(lambda (response &optional span oc extra)
     (cedille-mode-response ,fn response span oc extra)))

(provide 'cedille-mode-normalize)
