-- Clicks the first button in VideoPlayer's window whose name or description contains the given text.
-- Usage: osascript click.applescript "NEXT"
-- With "--list" it prints every button it can see instead.
on run argv
	set target to item 1 of argv
	set found to {}
	tell application "System Events"
		tell process "VideoPlayer"
			set frontmost to true
			repeat with e in (entire contents of window 1)
				try
					if role of e is "AXButton" then
						set n to ""
						set d to ""
						try
							set n to (name of e) as text
						end try
						try
							set d to (description of e) as text
						end try
						if target is "--list" then
							set end of found to (n & " | " & d)
						else if (n contains target) or (d contains target) then
							click e
							return "clicked: " & n & " | " & d
						end if
					end if
				end try
			end repeat
		end tell
	end tell
	if target is "--list" then
		set AppleScript's text item delimiters to linefeed
		return found as text
	end if
	return "NOT FOUND: " & target
end run
