;;; chronometrist-goals.el --- Adds support for time goals to Chronometrist -*- lexical-binding: t; -*-

;; Author: contrapunctus <xmpp:contrapunctus@jabber.fr>
;; Maintainer: contrapunctus <xmpp:contrapunctus@jabber.fr>
;; Keywords: calendar
;; Homepage: https://github.com/contrapunctus-1/chronometrist
;; Package-Requires: ((emacs "25.1") (alert "1.2") (chronometrist "0.5.0"))
;; Version: 0.1.0

(require 'chronometrist-queries)
(require 'alert)

;;; Commentary:

;;; It is hoped that `chronometrist-goals-alert-functions' provides a good balance
;;; of flexibility and ease of use for the majority of use cases. A
;;; user desiring even greater control may define their own versions
;;; of `chronometrist-goals-run-alert-timers' and `chronometrist-goals-stop-alert-timers' (preferably using
;;; them as a template) and add them to the desired hooks.

;; TODO -
;; * clear notifications on file change event
;; * define types for custom variables
;; * clock in -> go over the goal, get the 'exceeding' -> clock out, file changes, the exceed alert is shown again

;;; Code:

(declare-function chronometrist-last "chronometrist-queries")

(defvar chronometrist--timers-list nil)

(defcustom chronometrist-goals-list nil
  "List to specify daily time goals for each task.
Each element must be in the form (GOAL TASK *).

GOAL is an integer specifying number of minutes.

TASK is the task on which you would like spend GOAL time.

There can be more than one TASK, to specify that you would
like to spend GOAL time on any one of those tasks."
  :group 'chronometrist
  :type '(repeat
          (list integer :value 15
                (repeat :inline t string))))

(defun chronometrist-run-at-time (time repeat function &rest args)
  "Like `run-at-time', but append timers to `chronometrist--timers-list'."
  (->> (apply #'run-at-time time repeat function args)
       (list)
       (append chronometrist--timers-list)
       (setq chronometrist--timers-list)))

;; (mapcar #'chronometrist-seconds->alert-string '(0 1 2 59 60 61 62 120 121 122))
(defun chronometrist-seconds->alert-string (seconds)
  "Convert SECONDS to a string suitable for displaying in alerts.
SECONDS should be a positive integer."
  (-let [(h m _) (chronometrist-seconds-to-hms seconds)]
    (let* ((h-str  (unless (zerop h)
                     (number-to-string h)))
           (m-str  (unless (zerop m)
                     (number-to-string m)))
           (h-unit (cl-case h
                     (0 nil)
                     (1 " hour")
                     (t " hours")))
           (m-unit (cl-case m
                     (0 nil)
                     (1 " minute")
                     (t " minutes")))
           (and    (if (and h-unit m-unit)
                       " and "
                     "")))
      (concat h-str h-unit
              and
              m-str m-unit))))

(defun chronometrist-approach-alert (task goal spent)
  "Alert the user when they are 5 minutes away from reaching GOAL for TASK.
TASK is the name of the current task (as a string).
GOAL is the goal time for that task (minutes as an integer).
SPENT is the time spent on that task (minutes as an integer)."
  (and goal
       (< spent goal)
       (chronometrist-run-at-time (* 60 (- goal 5 spent)) ;; negative seconds = run now
                      nil
                      (lambda (task)
                        (alert (format "5 minutes remain for %s" task)))
                      task)))

(defun chronometrist-complete-alert (task goal spent)
  "Alert the user when they have reached the GOAL for TASK.
TASK is the name of the current task (as a string).
GOAL is the goal time for that task (minutes as an integer).
SPENT is the time spent on that task (minutes as an integer)."
  (and goal
       ;; In case the user reaches GOAL but starts tracking again -
       ;; CURRENT is slightly over GOAL, but we notify the user of
       ;; reaching the GOAL anyway.
       (< spent (+ goal 5))
       (chronometrist-run-at-time (* 60 (- goal spent)) ;; negative seconds = run now
                      nil
                      (lambda (task)
                        (alert (format "Goal for %s reached" task)))
                      task)))

(defun chronometrist-exceed-alert (task goal spent)
  "Alert the user when they have exceeded the GOAL for TASK.
TASK is the name of the current task (as a string).
GOAL is the goal time for that task (minutes as an integer).
SPENT is the time spent on that task (minutes as an integer)."
  (and goal
       (chronometrist-run-at-time (* 60 (- (+ goal 5) spent)) ;; negative seconds = run now
                      nil
                      (lambda (task)
                        (alert (format "You are exceeding the goal for %s!" task)
                               :severity 'medium))
                      task)))

(defun chronometrist-no-goal-alert (task goal _spent)
  "If TASK has no GOAL, regularly remind the user of the time spent on it.
TASK is the name of the current task (as a string).
GOAL is the goal time for that task (minutes as an integer).
SPENT is the time spent on that task (minutes as an integer)."
  (unless goal
    (chronometrist-run-at-time (* 15 60) ;; first run after 15 minutes from now
                   (* 15 60) ;; repeat every 15 minutes
                   (lambda (task)
                     ;; We cannot use SPENT here, because that will
                     ;; remain the value it had when we clocked in
                     ;; (when `chronometrist-goals-run-alert-timers'
                     ;; is run), and we need show the time spent at
                     ;; the time of notification.
                     (alert (format "You have spent %s on %s"
                                    (chronometrist-seconds->alert-string
                                     (chronometrist-task-time-one-day task))
                                    task)))
                   task)))

(defcustom chronometrist-goals-alert-functions
  '(chronometrist-approach-alert
    chronometrist-complete-alert
    chronometrist-exceed-alert
    chronometrist-no-goal-alert)
  "List to describe timed alerts.
Each element should be a function, which will be called with
three arguments - the name of the current task (as a string) and
the goal time for that task (minutes as an integer), and the time
spent on that task (minutes as an integer).

Typically, each function in this list should call `run-at-time'
to run another function, which in turn should call `alert' to
notify the user.

The timer returned by `run-at-time' should also be appended to
`chronometrist--timers-list', so that it can later be stopped by
`chronometrist-goals-stop-alert-timers'. `chronometrist-run-at-time'
will do that for you.

Note - the time spent passed to these functions is calculated
when `chronometrist-goals-run-alert-timers' is run, i.e. when the
user clocks in. To obtain the time spent at the time of
notification, use `chronometrist-task-time-one-day' within the
function passed to `run-at-time'."
  :group 'chronometrist
  :type 'hook)

;; TODO - if there are multiple tasks associated with a single time
;; goal (i.e. `(int "task1" "task2" ...)'), and the user has reached
;; the goal for one of those tasks, don't display the goal for the
;; other associated tasks
(cl-defun chronometrist-get-goal (task &optional (goals-list chronometrist-goals-list))
  "Return time goal for TASK from GOALS-LIST.
Return value is minutes as an integer, or nil.

If GOALS-LIST is not supplied, `chronometrist-goals-list' is used."
  (cl-loop for list in goals-list
           when (member task list)
           return (car list)))

(defun chronometrist-goals-run-alert-timers (task)
  "Run timers to alert the user of the time spent on TASK.
To use, add this to `chronometrist-after-in-functions', and
`chronometrist-goals-stop-alert-timers' to
`chronometrist-after-out-functions'."
  (let ((goal    (chronometrist-get-goal task))
        (spent   (/ (chronometrist-task-time-one-day task) 60)))
    (add-hook 'chronometrist-file-change-hook #'chronometrist-goals-on-file-change)
    (mapc (lambda (f)
            (funcall f task goal spent))
          chronometrist-goals-alert-functions)))

(defun chronometrist-goals-stop-alert-timers (&optional _task)
  "Stop timers to alert the user of the time spent on TASK.
To use, add this to `chronometrist-after-out-functions', and
`chronometrist-goals-run-alert-timers' to
`chronometrist-after-in-functions'."
  (and chronometrist--timers-list ;; in case of start task -> exit Emacs without stopping -> start Emacs -> stop task
       (mapc #'cancel-timer chronometrist--timers-list)
       (setq chronometrist--timers-list   nil)))

(defun chronometrist-goals-on-file-change ()
  "Manage timed alerts when `chronometrist-file' changes."
  (let ((last (chronometrist-last)))
    (chronometrist-goals-stop-alert-timers)
    ;; if there's a task running, start timed alerts for it
    (unless (plist-get last :stop)
      (chronometrist-goals-run-alert-timers (plist-get last :name)))))

(provide 'chronometrist-goals)

;; Local Variables:
;; nameless-current-name: "chronometrist-goals"
;; End:

;;; chronometrist-goals.el ends here
