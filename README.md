# mu4e-detach

Detach email attachments in mu4e by saving them to a folder and (optionally)
removing the attachment from the message. A short text is appended to the
message with a list of the removed attachments.

This package adds actions to headers-view and message-view.

By default, it only saves the attachments and does not remove them.

To enable removing the attachments, eval the following:

~~~ elisp
(setq mu4e-detach-remove t)
~~~

Further settings:

~~~ elisp
(defcustom mu4e-detach-save-all-attachments-folder-base "~/Downloads/attachments"
  "Base folder for saving. For each message, a new folder is
  created for saving attachments."
  :group 'mu4e-detach
  :type 'string)

(defcustom mu4e-detach-save t
  "Controls if attachments should be saved."
  :group 'mu4e-detach
  :type 'boolean)

(defcustom mu4e-detach-remove nil
  "Controls if attachments should be removed."
  :group 'mu4e-detach
  :type 'boolean)

(defcustom mu4e-detach-append-removed-filenames t
  "Controls if the list of removed file names should be appended
  to the message."
  :group 'mu4e-detach
  :type 'boolean)
~~~

Loading in a Spacemacs layer:

~~~ elisp
// mu4e/packages.el

(setq mu4e-packages
      '(;; ...
        mu4e-detach
        ;; ...
        ))

;; ...

(defun mu4e/init-mu4e-detach ()
  (use-package mu4e-detach
    :defer t
    :init (with-eval-after-load 'mu4e (mu4e-detach/load))))
~~~

The 'altermime' tool is used to change the messages. Install with your
distribution's package manager. On Ubuntu:

~~~
sudo apt-get install altermime
~~~
