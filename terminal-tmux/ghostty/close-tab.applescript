on run argv
	if (count of argv) is not 1 then error "close-tab requires one Ghostty tab ID"
	set targetTabID to item 1 of argv

	tell application "Ghostty"
		repeat with candidateWindow in windows
			repeat with candidateTab in tabs of candidateWindow
				if (id of candidateTab as text) is targetTabID then
					close tab candidateTab
					return true
				end if
			end repeat
		end repeat
	end tell

	return false
end run
