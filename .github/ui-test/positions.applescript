-- Prints where VideoPlayer's buttons and setlist rows are on screen, one per line:
--   BUTTON|name|description|x|y|width|height
--   ROW|||x|y|width|height        (setlist rows, top to bottom)
-- The UI test clicks the middle of these, so it keeps working when the layout changes.
on run argv
	set out to {}
	tell application "System Events"
		tell process "VideoPlayer"
			set frontmost to true
			repeat with e in (entire contents of window 1)
				try
					set r to role of e
					if r is "AXButton" or r is "AXRow" then
						set p to position of e
						set s to size of e
						set n to ""
						set d to ""
						if r is "AXButton" then
							try
								set n to (name of e) as text
							end try
							try
								set d to (description of e) as text
							end try
							set kind to "BUTTON"
						else
							set kind to "ROW"
						end if
						set end of out to kind & "|" & n & "|" & d & "|" & ((item 1 of p) as integer) & "|" & ((item 2 of p) as integer) & "|" & ((item 1 of s) as integer) & "|" & ((item 2 of s) as integer)
					end if
				end try
			end repeat
		end tell
	end tell
	set AppleScript's text item delimiters to linefeed
	return out as text
end run
