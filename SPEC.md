# LaunchdLens — specification

**Tagline:** Browse, create and schedule launchd jobs with a friendly editor instead of hand-writing property list files.

**Category:** Developer & Network

**Inspired by (paid):** Lingon X ($14.99 one-time)

**Frameworks:** SwiftUI, AppKit, Foundation, UniformTypeIdentifiers

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does and evidence of demand. Lingon X is a graphical editor for launchd, the macOS system that starts and schedules background jobs. It lets people run a script at a time, keep an app alive, or run something at login without writing property lists by hand. Macworld reviewed it at about 14.99 dollars with praise for both beginners and advanced users, and developers and sysadmins keep recommending it on forums as the friendly alternative to cron. Our version covers per-user launch agents only, which needs no admin rights.

Feature set for our clean-room version. A window app. A sidebar lists launch agents found in the user's LaunchAgents folder, with a status dot showing loaded or not loaded and the last exit status. Selecting one shows an editor form with Label, Program and arguments, Run at load, Keep alive, Start interval in seconds, Calendar schedule (minute, hour, weekday, day), Working directory, Standard output path and Standard error path. A New Job button opens a template picker: Run script on a schedule, Run at login, Keep an app running and Run when a folder changes with WatchPaths. Buttons: Save, Load, Unload, Run Now, Reveal in Finder, Show Log and Delete. A read-only raw view shows the generated property list.

UI spec. A NavigationSplitView with the list at left and the form at right. The form validates as you type and shows a red note beside invalid fields, such as a missing program path or a label that does not follow reverse-domain style. A bottom bar shows the result text of the last [removed] action. The toolbar has New, Reload List and a search field. Settings are minimal: a default label prefix with an editable default of the user's reverse-domain name, and a toggle to also show read-only third-party agents installed by other apps. Empty state: a short explanation of what launch agents are and a button to create a first job from a template. Keyboard: Command N for new, Command S for save, Command R for run now.

Technical approach. Read and write property lists with PropertyListSerialization using dictionaries for the known keys, preserving unknown keys on round trip so existing files are not damaged. Place files in the LaunchAgents folder of the user library and write atomically. Use Foundation Process to call the [removed] command with bootstrap, bootout, kickstart and print subcommands for the user's gui domain, using the current user id, and capture output into the status bar. Read job status by parsing the output of [removed] list. Log viewing opens the configured output file in a scrolling text view with a tail that refreshes every two seconds. No privileged helper is used, so system-wide daemons are explicitly out of scope and the UI says so.

Edge cases and error handling. Warn before overwriting a file not created by this app. Refuse to save when the program path does not exist or is not executable and offer a file picker. Convert a friendly schedule such as every weekday at 9 into the proper calendar interval array and show the plain-language summary back. Show a clear message when [removed] returns an error code and keep the failure text visible. If the file changes on disk while editing, offer to reload. Unloading a job before deletion is enforced. Keep the code near 600 lines.
