;;; scimax-twitter.el --- Twitter functions

;;; Commentary:
;;
;; Install the commandline twitter from https://github.com/sferik/t
;; There was a bug described in https://github.com/sferik/t/issues/395
;; I installed an older version like this (uses Ruby).
;; gem install t -v 2.10
;;
;; Then run: t authorize
;;
;; to setup authorization for your twitter account.
;;
;; Send a tweet from a program: `scimax-twitter-update'.
;; Reply to a tweet from a program: `scimax-twitter-reply'
;;
;; Tweet from an org headline: `scimax-twitter-tweet-headline'
;;
;; `scimax-twitter-ivy' an interface to your followers and followees.
;;
;; Tweet a subtree as a thread: `scimax-twitter-org-subtree-tweet-thread'
;; TODO: check for lengths before trying to send.
;;
(require 'f)
(require 'scimax-functional-text)

;; * Hashtag functional text
(scimax-functional-text
 "\\(^\\|[[:punct:]]\\|[[:space:]]\\)\\(?2:#\\(?1:[[:alnum:]]+\\)\\)"
 (lambda ()
   (browse-url (format "https://twitter.com/hashtag/%s" (match-string 1))))
 :grouping 2
 :face (list 'org-link)
 :help-echo "Click me to open hashtag.")


;; * Twitter handles
(scimax-functional-text
 "\\(^\\|[[:punct:]]\\|[[:space:]]\\)\\(?2:@\\(?1:[[:alnum:]]+\\)\\)"
 (lambda ()
   (browse-url (format "https://twitter.com/%s" (match-string 1))))
 :grouping 2
 :face (list 'org-link)
 :help-echo "Click me to open username.")


;; * Twitter usernames

(defcustom scimax-twitter-directory "~/.scimax-twitter/"
  "Directory to cache scimax-twitter data.")


(unless (f-dir? scimax-twitter-directory)
  (make-directory scimax-twitter-directory t))


(defun scimax-twitter-download-whois-info (&optional reload)
  "Download info on who you follow and followers."
  (interactive "P")

  (when (or reload (null scimax-twitter-usernames))
    (setq scimax-twitter-usernames (-uniq (append (process-lines "t" "followings")
						  (process-lines "t" "followers")
						  (process-lines "t" "followings")
						  (process-lines "t" "leaders")
						  (process-lines "t" "groupies")))))

  (unless (f-dir? (f-join scimax-twitter-directory "whois"))
    (make-directory (f-join scimax-twitter-directory "whois") t))

  ;; Here we download the files if necessary.
  (loop for username in scimax-twitter-usernames
	do
	(let ((userfile (expand-file-name username
					  (f-join scimax-twitter-directory "whois"))))
	  (when (or reload (not (f-exists? userfile)))
	    (with-temp-file userfile
	      (insert (shell-command-to-string
		       (format "t whois %s" username))))))))


(defvar scimax-twitter-usernames nil
  "List of usernames that either you follow or that follow you.")


(defvar scimax-twitter-ivy-candidates '()
  "List of candidate usernames for ivy.")


(defun scimax-twitter-ivy-candidates (&optional reload)
  "Returns a list of candidates"
  (interactive "P")
  (when (or reload (null scimax-twitter-usernames))
    (setq scimax-twitter-usernames (-uniq (append (process-lines "t" "followings")
						  (process-lines "t" "followers")))))
  (when (or reload (null scimax-twitter-ivy-candidates))
    (setq scimax-twitter-ivy-candidates
	  (loop for username in scimax-twitter-usernames
		collect
		(let* ((userfile (expand-file-name username
						   (f-join scimax-twitter-directory "whois")))
		       (info (when (f-exists? userfile)
			       (mapcar (lambda (line)
					 (cons (s-trim (substring line 0 13))
					       (substring line 13)))
				       (process-lines "cat" userfile)))))
		  (list (format "%20s | %20s | %40s | %s"
				(cdr (assoc "Screen name" info))
				(cdr (assoc "Name" info))
				(cdr (assoc "Bio" info))
				(cdr (assoc "URL" info)))
			info)))))
  ;; return the variable
  scimax-twitter-ivy-candidates)


(defun scimax-twitter-ivy (&optional reload)
  "Select from who you follow and your followers with ivy.
Default action is to insert the screen name, but you can also
open their twitter page or url."
  (interactive "P")
  (ivy-read "Username: " (scimax-twitter-ivy-candidates reload)
	    :action '(1
		      ("i" (lambda (cand)
			     (let ((info (cadr cand)))
			       (insert (cdr (assoc "Screen name" info)))))
		       "insert username")
		      ("d" (lambda (cand)
			     (let* ((info (cadr cand))
				    (user (cdr (assoc "Screen name" info)))
				    (msg (read-input "Msg: ")))
			       (message (s-join "\n" (process-lines "t" "dm" user msg)))))
		       "direct message")
		      ("f" (lambda (cand)
			     (let* ((info (cadr cand))
				    (user (cdr (assoc "Screen name" info))))
			       (message (s-join "\n" (process-lines "t" "follow" user)))))
		       "follow")
		      ;; list commands seem to be broken.
		      ;; /usr/local/bin/t: Sorry, that page does not exist.
		      ;; ("l" (lambda (cand)
		      ;; 	     (let* ((info (cadr cand))
		      ;; 		    (user (cdr (assoc "Screen name" info)))
		      ;; 		    (list (completing-read
		      ;; 			   "List: "
		      ;; 			   (process-lines "t" "lists"))))
		      ;; 	       (message (s-join "\n" (process-lines "t" "list" "add"
		      ;; 						    list user)))))
		      ;;  "add to list")
		      ("M" (lambda (cand)
			     (let* ((info (cadr cand))
				    (user (cdr (assoc "Screen name" info))))
			       (message (s-join "\n" (process-lines "t" "mute" user)))))
		       "Mute")
		      ;; TODO: update variable? remove whois entry?
		      ("U" (lambda (cand)
			     (let* ((info (cadr cand))
				    (user (cdr (assoc "Screen name" info))))
			       (message (s-join "\n" (process-lines "t" "unfollow" user)))))
		       "unfollow")
		      ("o" (lambda (cand)
			     (let* ((info (cadr cand))
				    (user (cdr (assoc "Screen name" info))))
			       (message (s-join "\n" (process-lines "t" "open" user)))))
		       "Open profile")
		      ("u" (lambda (cand)
			     (let ((info (cadr cand)))
			       (browse-url (cdr (assoc "URL" info)))))
		       "Open their url")
		      ("w" (lambda (cand)
			     (let* ((info (cadr cand))
				    (user (cdr (assoc "Screen name" info))))
			       (message (s-join "\n" (process-lines "t" "whois" user)))))
		       "whois"))))



;; * Tweet functions

(defun scimax-twitter-update (msg &optional file)
  "Post MSG as a tweet with an optional media FILE.
Returns the msgid for the posted tweet or the output from t."
  (interactive (list (read-input "Msg: ")
		     (read-file-name "File: ")))

  (unless (and file (f-ext? file "png"))
    (setq file nil))

  ;; This will convert org-entities to utf-8 chars
  (setq msg (org-export-string-as msg 'twitter t '(:ascii-charset utf-8)))

  (let* ((output (apply 'process-lines `("t" "update" ,msg
					 ,@(when file '("-f"))
					 ,@(when file `(,file)))))
	 (last-line (car (last output))))
    (if (string-match "`t delete status \\([0-9]*\\)`" last-line)
	(prog1
	    (match-string-no-properties 1 last-line)
	  (org-entry-put nil "TWEETED_AT"
			 (format-time-string "<%Y-%m-%d %a %H:%M>")))
      ;; this probably means there was an error.
      last-line)))


(defun scimax-twitter-reply (msg msgid &optional file)
  "Reply MSG to tweet with MSGID and optional media FILE.
Returns the msgid for the posted tweet or the output from t."

  (setq msg (org-export-string-as msg 'twitter t '(:ascii-charset utf-8)))

  (let* ((output (apply 'process-lines `("t" "reply" ,msgid ,msg
					 ,@(when file '("-f"))
					 ,@(when file `(,file)))))
	 (last-line (car (last output))))
    (if (string-match "`t delete status \\([0-9]*\\)`" last-line)
	(prog1
	    (match-string-no-properties 1 last-line)
	  (match-string-no-properties 1 last-line))
      last-line)))


(defmacro scimax-twitter-tweet-thread (&rest tweets)
  "Each tweet is a list of msg and optional file.
After the first tweet, each remaining tweet is a reply to the
last one."
  ;; Send the first one.
  (let (msgid
	(tweet (pop tweets)))
    (setq msgid (apply 'tweet (if (stringp tweet)
				  (list tweet)
				tweet)))
    ;; now send the rest of them
    (while tweets
      (setq tweet (pop tweets)
	    msgid (apply 'tweet-reply `(,msgid ,@(if (stringp tweet)
						     (list tweet)
						   tweet)))))))


;; * Twitter - org integration

(defun scimax-twitter-org-reply-p ()
  "For the current headline, determine if it is a reply to another tweet.
It is if the previous heading has TWITTER_MSGID property, and the
current headline is tagged as part of a tweet thread. Returns the
id to reply to if those conditions are met."
  (let ((tags (mapcar 'org-no-properties (org-get-tags-at))))
    (or (org-entry-get nil "TWITTER_IN_REPLY_TO")
	(and (-contains?  tags "tweet")
	     (-contains? tags "thread")
	     (save-excursion
	       (unless (looking-at org-heading-regexp)
		 (org-back-to-heading))
	       (org-previous-visible-heading 1)
	       ;; Make sure previous heading is part of the thread
	       (let ((tags (mapcar 'org-no-properties (org-get-tags-at))))
		 (and (-contains?  tags "tweet")
		      (-contains? tags "thread")
		      (org-entry-get nil "TWITTER_MSGID"))))))))


(defun scimax-twitter-org-tweet-components ()
  "Get the components required for tweeting a headline.
This is a list of (message reply-id file) where message is a
string that will be the tweet, reply-id is a string of the id to
reply to (it may be nil), and file is an optional media file to
attach to the tweet. If there are code blocks with a :gist in the
header, they will be uploaded as a gist, and the link added to
the msg. "
  (let (msg
	reply-id
	file
	gists
	cp
	latex-frag
	next-heading)

    (save-excursion
      (unless (looking-at org-heading-regexp)
	(org-back-to-heading))
      (setq cp (point)
	    msg (nth 4 (org-heading-components))
	    reply-id (scimax-twitter-org-reply-p)))

    ;; check for files to attach
    (save-excursion
      (when (looking-at org-heading-regexp) (forward-char))
      (setq next-heading (re-search-forward org-heading-regexp nil t 1)))

    (save-restriction
      (narrow-to-region cp (or next-heading (point-max)))
      (setq file (car (org-element-map (org-element-parse-buffer) 'link
			(lambda (link)
			  (when
			      (and
			       (string= "file" (org-element-property :type link))
			       (f-ext? (org-element-property :path link) "png"))
			    (org-element-property :path link))))))
      ;; latex fragments overrule files.
      (setq latex-frag (car (org-element-map (org-element-parse-buffer)
				'(latex-environment latex-fragment) 'identity)))
      (when latex-frag
	(goto-char (org-element-property :begin latex-frag))
	(unless (ov-at) (org-toggle-latex-fragment))
	(setq file (plist-get (cdr (overlay-get (ov-at) 'display)) :file)))

      ;; src-blocks
      (setq gists (org-element-map (org-element-parse-buffer) 'src-block
		    (lambda (src)
		      (when (and (stringp (org-element-property :parameters src))
				 (s-contains? ":gist" (org-element-property :parameters src)))
			(save-excursion
			  (goto-char (org-element-property :begin src))
			  (org-edit-special)
			  (gist-buffer)
			  (org-edit-src-abort)
			  (org-no-properties (pop kill-ring))))))))
    (when gists (setq msg (s-concat msg " " (s-join " " gists))))

    (list msg reply-id file)))


(defun scimax-twitter-tweet-headline (&optional force)
  "Tweet a headline.
The headline itself is the tweet, and the first image is
attached. If the headline is in a :tweet:thread:, reply if
necessary. Adds properties to the headline so you know what was
done."
  (interactive "P")
  (unless force
    (when (org-entry-get nil "TWITTER_MSGID")
      (user-error "This headline has already been tweeted.")))

  (when-let (account (org-entry-get nil "TWITTER_ACCOUNT" t))
    (shell-command (format "t set active %s" account)))

  (let* ((components (scimax-twitter-org-tweet-components))
	 (msgid (if (not (null (nth 1 components)))
		    ;; reply
		    (apply 'scimax-twitter-reply components)
		  (scimax-twitter-update (nth 0 components) (nth 2 components)))))
    (when (not (null (nth 1 components)))
      (org-entry-put nil "TWITTER_IN_REPLY_TO" (nth 1 components)))
    (org-entry-put nil "TWITTER_MSGID" msgid)
    (let* ((output (process-lines "t" "accounts"))
	   ;; Note: this may break if you have multiple keys on an account.
	   (i (-find-index
	       (lambda (s)
		 (s-contains? "(active)" s))
	       output))
	   (username (nth (- i 1) output)))
      (org-entry-put nil "TWITTER_URL" (format "https://twitter.com/%s/status/%s"
					       username
					       msgid)))
    (message "%s" components)))

;; Replace the speed command
(setf (cdr (assoc "T" org-speed-commands-user)) 'scimax-twitter-tweet-headline)


(defun scimax-twitter-org-subtree-tweet-thread ()
  "Tweet the subtree as a thread."
  (interactive)

  (when-let (account (org-entry-get nil "TWITTER_ACCOUNT" t))
    (shell-command (format "t set active %s" account)))

  (save-restriction
    (org-narrow-to-subtree)

    (save-excursion
      (goto-char (point-min))
      (unless (-contains?  (mapcar 'org-no-properties (org-get-tags-at)) "tweet")
	(let ((current-tags (org-get-tags-at)))
	  (org-set-tags-to (append current-tags '("tweet")))))

      (unless (-contains?  (mapcar 'org-no-properties (org-get-tags-at)) "thread")
	(let ((current-tags (org-get-tags-at)))
	  (org-set-tags-to (append current-tags '("thread")))))

      (while (looking-at org-heading-regexp)
	(scimax-twitter-tweet-headline)
	(org-next-visible-heading 1)))))


(defun scimax-twitter-clear-thread-properties ()
  "Clear the Twitter properties in the subtree."
  (interactive)
  (save-restriction
    (org-narrow-to-subtree)
    (save-excursion
      (goto-char (point-min))
      (while (looking-at org-heading-regexp)
	(org-entry-delete nil "TWITTER_URL")
	(org-entry-delete nil "TWITTER_MSGID")
	(org-entry-delete nil "TWITTER_IN_REPLY_TO")
	(org-next-visible-heading 1)))))

;; * Miscellaneous utilities

(defun scimax-twitter-status ()
  "Show status of tweet in current headline."
  (interactive)
  (message
   (shell-command-to-string
    (format "t status %s" (org-entry-get nil "TWITTER_MSGID")))))


(defun scimax-twitter-delete-status ()
  "Delete the tweet in the current headline."
  (interactive)
  (prog1
      (message
       (shell-command-to-string
	(format "echo y | t delete status %s" (org-entry-get nil "TWITTER_MSGID"))))
    (org-entry-put nil "TWITTER_MSGID" (concat (org-entry-get nil "TWITTER_MSGID")
					       " - deleted"))
    (org-entry-delete nil "TWITTER_URL")))


(defun scimax-twitter-delete-thread ()
  "Delete the tweets in the thread."
  (interactive)
  (save-restriction
    (org-narrow-to-subtree)
    (goto-char (point-min))
    (while (looking-at org-heading-regexp)
      (scimax-twitter-delete-status)
      (org-next-visible-heading 1))))


(defun scimax-twitter-dm (user msg)
  "Send USER a MSG by dm."
  (interactive
   (list
    (completing-read "User: " scimax-twitter-usernames)
    (read-input "Msg: ")))
  (message (shell-command-to-string
	    (format "t dm %s \"%s\"" user msg))))


(defun scimax-twitter-set-account (user)
  "Set the account to tweet from."
  (interactive (list (completing-read
		      "Account: "
		      (-slice (process-lines "t" "accounts") 0 -1 2))))
  (message (shell-command-to-string (format "t set active %s" user))))


;; * Exporter
;; http://qaz.wtf/u/convert.cgi?text=ABCDEFGHIJKLMNOPQRSTUVWZYZabcdefghijklmnopqrstuvwxyz0123456789
(defun scimax-twitter-filter-bold (text back-end info)
  (let ((plain "ABCDEFGHIJKLMNOPQRSTUVWZYZabcdefghijklmnopqrstuvwxyz0123456789")
	(ubold "𝐀𝐁𝐂𝐃𝐄𝐅𝐆𝐇𝐈𝐉𝐊𝐋𝐌𝐍𝐎𝐏𝐐𝐑𝐒𝐓𝐔𝐕𝐖𝐗𝐘𝐙𝐚𝐛𝐜𝐝𝐞𝐟𝐠𝐡𝐢𝐣𝐤𝐥𝐦𝐧𝐨𝐩𝐪𝐫𝐬𝐭𝐮𝐯𝐰𝐱𝐲𝐳𝟎𝟏𝟐𝟑𝟒𝟓𝟔𝟕𝟖𝟗")
	i)
    (replace-regexp-in-string "*" ""
			      (s-join "" (loop for letter across text collect
					       (progn
						 (setq i (s-index-of
							  (char-to-string letter)
							  plain))
						 (if i (substring ubold  i (incf i))
						   (char-to-string letter))))))))


(defun scimax-twitter-filter-italic (text back-end info)
  (let ((plain "ABCDEFGHIJKLMNOPQRSTUVWZYZabcdefghijklmnopqrstuvwxyz0123456789")
	(uitalic "𝐴𝐵𝐶𝐷𝐸𝐹𝐺𝐻𝐼𝐽𝐾𝐿𝑀𝑁𝑂𝑃𝑄𝑅𝑆𝑇𝑈𝑉𝑊𝑋𝑌𝑍𝑎𝑏𝑐𝑑𝑒𝑓𝑔ℎ𝑖𝑗𝑘𝑙𝑚𝑛𝑜𝑝𝑞𝑟𝑠𝑡𝑢𝑣𝑤𝑥𝑦𝑧")
	i)
    (replace-regexp-in-string "/" ""
			      (s-join "" (loop for letter across text collect
					       (progn
						 (setq i (s-index-of
							  (char-to-string letter)
							  plain))
						 (if i (substring uitalic  i (incf i))
						   (char-to-string letter))))))))


(defun scimax-twitter-filter-verbatim (text back-end info)
  (let ((plain "ABCDEFGHIJKLMNOPQRSTUVWZYZabcdefghijklmnopqrstuvwxyz0123456789")
	(uverbatim "𝙰𝙱𝙲𝙳𝙴𝙵𝙶𝙷𝙸𝙹𝙺𝙻𝙼𝙽𝙾𝙿𝚀𝚁𝚂𝚃𝚄𝚅𝚆𝚉𝚈𝚉𝚊𝚋𝚌𝚍𝚎𝚏𝚐𝚑𝚒𝚓𝚔𝚕𝚖𝚗𝚘𝚙𝚚𝚛𝚜𝚝𝚞𝚟𝚠𝚡𝚢𝚣𝟶𝟷𝟸𝟹𝟺𝟻𝟼𝟽𝟾𝟿")
	i)
    (replace-regexp-in-string
     "`\\|'" ""
     (s-join "" (loop for letter across text collect
		      (progn
			(setq i (s-index-of
				 (char-to-string letter)
				 plain))
			(if i (substring uverbatim  i (incf i))
			  (char-to-string letter))))))))


(defun scimax-twitter-export-headline (&rest args)
  "Pseudo-export function for tweeting a headline."
  (interactive)
  (scimax-twitter-tweet-headline))


(defun scimax-twitter-export-headline-force (&rest args)
  "Pseudo-export function for force tweeting a headline."
  (interactive)
  (scimax-twitter-tweet-headline t))


(defun scimax-twitter-export-subtree (&rest args)
  "Pseudo-export function for tweeting a subtree as a thread."
  (interactive)
  (scimax-twitter-org-subtree-tweet-thread))

(defun scimax-twitter-export-delete (&rest args)
  "Pseudo-export function for deleting a tweet in a headline."
  (scimax-twitter-delete-status))


(org-export-define-derived-backend 'twitter 'ascii
  :filters-alist '((:filter-bold . scimax-twitter-filter-bold)
		   (:filter-italic . scimax-twitter-filter-italic)
		   (:filter-verbatim . scimax-twitter-filter-verbatim))
  :menu-entry
  '(?w "Export with scimax-twitter"
       ((?h "Headline" scimax-twitter-export-headline)
	(?H "Headline (force)" scimax-twitter-export-headline-force)
	(?s "Subtree" scimax-twitter-export-subtree)
	(?d "delete" scimax-twitter-export-delete))))

;; * scheduling tweets

(unless (f-dir? (f-join scimax-twitter-directory "scheduled-tweets"))
  (make-directory (f-join scimax-twitter-directory "scheduled-tweets") t))


(defun scimax-twitter-schedule-tweet ()
  "This sets a tweet to be scheduled.
This creates a file to be loaded later."
  (interactive)
  (let* ((id (org-id-get-create))
	 (datafile (expand-file-name
		    (concat (org-entry-get nil "ID") ".el")
		    (f-join scimax-twitter-directory "scheduled-tweets")))
	 (data `(progn
		  (find-file ,(buffer-file-name))
		  (re-search-forward ,id)
		  (when (org-time>
			 ;; current-time
			 (format-time-string "<%Y-%m-%d %a %H:%M>")
			 ;; scheduled entry time
			 ,(format-time-string
			   "<%Y-%m-%d %a %H:%M>" (org-get-scheduled-time nil)))
		    (scimax-twitter-tweet-headline)
		    (org-todo "DONE")
		    (org-entry-put nil "TWEETED_AT"
				   (format-time-string "<%Y-%m-%d %a %H:%M>"))
		    (f-delete ,datafile)))))

    (with-temp-file datafile
      (pp data (current-buffer)))
    (org-entry-put nil "TWEET_SCHEDULED" datafile)))


(defun scimax-twitter-process-scheduled ()
  (interactive)
  (loop for file in
	(f-files (f-join scimax-twitter-directory "scheduled-tweets"))
	do
	(message "Loading %s" file)
	(load-file file)))


(provide 'scimax-twitter)

;;; scimax-twitter.el ends here
