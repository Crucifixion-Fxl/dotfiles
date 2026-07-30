on run argv
	if (count of argv) is not 5 then error "ghostty-dev requires a wrapper, state directory, close script, command, and one argument"

	set wrapperPath to item 1 of argv
	set stateDirectory to item 2 of argv
	set closeScriptPath to item 3 of argv
	set commandPath to item 4 of argv
	set commandArgument to item 5 of argv
	-- Ghostty 的 AppleScript command 字段已经按 shell 命令执行；这里不能再加
	-- config 文件支持的 shell:/direct: 前缀，否则前缀会被当作可执行文件名。
	set surfaceCommand to quoted form of wrapperPath & " " & quoted form of stateDirectory & " " & quoted form of closeScriptPath & " " & quoted form of commandPath & " " & quoted form of commandArgument

	tell application "Ghostty"
		set surfaceConfig to new surface configuration
		set command of surfaceConfig to surfaceCommand
		set wait after command of surfaceConfig to false

		if (count of windows) is 0 then
			-- Ghostty 尚未打开窗口时只能创建首个窗口；正常使用时走下面的新 tab 分支。
			set targetWindow to new window with configuration surfaceConfig
			set targetTab to selected tab of targetWindow
		else
			set targetWindow to front window
			set targetTab to new tab in targetWindow with configuration surfaceConfig
			select tab targetTab
			activate window targetWindow
		end if

		-- Ghostty 1.3.1 偶尔不会执行 wait-after-command=false。把这个 tab 的稳定
		-- ID 交给 wrapper；远端命令结束后 wrapper 会精确关闭它，不依赖当前焦点。
		set targetTabID to id of targetTab as text
		set tabIDFile to stateDirectory & "/tab-id"
		do shell script "/usr/bin/printf '%s\\n' " & quoted form of targetTabID & " > " & quoted form of tabIDFile

		activate
	end tell
end run
