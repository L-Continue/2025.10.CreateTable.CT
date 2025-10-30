if syntaxcheck then return end
Global = Global or {}
Config = Config or {}

-- 辅助函数: 自定义打印函数（带行号和函数信息）
function prints(...)
	local DEBUG_MODE = Config.debugMode or 2
	if DEBUG_MODE == 0 then return end

	-- 处理各种参数情况
	local content, argCount = nil, select("#", ...)
	if argCount == 0 then content = "nil" end
	if argCount == 1 then content = ... == nil and "nil" or tostring(...) end
	if argCount >= 2 then content = string.format(...) end

	if DEBUG_MODE == 1 then print(content) return end

	if DEBUG_MODE == 2 then
		local debugInfo = debug.getinfo(2, "Sln")
		local linecount = debugInfo.currentline
		local funcname = debugInfo.name and " = " .. debugInfo.name .. " =" or ""
		printf("[%04d]%s %s", linecount, funcname, content)
	end
end

-- 辅助函数：异步延迟执行函数
function delay(delayTime, func)
	local timer = createTimer()
	timer.Interval = delayTime
	timer.OnTimer = function(sender) sender.destroy() func() end
end

-- 辅助函数: 大小格式化
function formatSize(bytes)
	local units = {"B", "KB", "MB", "GB", "TB"}
    if bytes == 0 then return "0 B" end

	local index = math.min(math.floor(math.log(bytes)/math.log(1024)), #units-1)
    local value = bytes/(1024^index)
	return string.format(index > 0 and "%.2f %s" or "%.0f %s", value, units[index+1])
end

-- 辅助函数: 提取":"后面的内容返回指定类型
function extractDescAs(id, targetType)
	local record = AddressList.getMemoryRecordByID(id)
	if not record then return end

	local result = record.Description:match(":%s*(.-)%s*$")
	if not result or result == "" then return end

	-- 根据目标类型返回不同结果
	if targetType == "N" then return tonumber(result) end
	if targetType == "B" then return result == "1" end
	if targetType == "T" then
		local tableResult = {}
		if result:find(",") then
			for item in result:gmatch("[^,]+") do
				local trimmed = item:match("^%s*(.-)%s*$")
				table.insert(tableResult, tonumber(trimmed) or trimmed)
			end
		else
			local trimmed = result:match("^%s*(.-)%s*$")
			if trimmed ~= "" then tableResult = {tonumber(trimmed) or trimmed} end
		end
		return tableResult
	end
	return result
end

-- 辅助函数: 读取子记录
function readSubRecords(id)
	local record = AddressList.getMemoryRecordByID(id)
	if not record or record.Count == 0 then return end
	for i = 1, record.Count do prints("[ %s ] %s", record.Description, record.Child[i-1].Description) end
end

-- 辅助函数：通过名称查找窗体
function findFormByName(name)
	if Global[name] then return Global[name] end
    for i = 0, getFormCount() - 1 do
        local form = getForm(i)
        if form and form.Name == name then Global[name] = form return form end
    end
    return nil
end

-- 添加额外菜单
function addExtraMenu()
	if Global.menuExists then return end
	-- 添加紧凑界面菜单
	local compactItem = createMenuItem(getMainForm().Menu.Items)
	compactItem.Caption = "紧凑界面"
	compactItem.OnClick = function(sender)
		sender.Caption = Global.compactEnabled and "紧凑界面" or "完整界面"
		control_setVisible(wincontrol_getControl(MainForm, 0), Global.compactEnabled)
		control_setVisible(wincontrol_getControl(MainForm, 3), Global.compactEnabled)
		-- 切换CompactUI状态
		Global.compactEnabled = not Global.compactEnabled

		local record = AddressList.getMemoryRecordByID(502)
		if record then record.Active = Global.compactEnabled end
	end
	Global.compactMenu = compactItem
	getMainForm().Menu.Items.add(compactItem)

	-- 添加符号表菜单
	local symbolItem = createMenuItem(getMainForm().Menu.Items)
	symbolItem.Caption = "符号表"
	symbolItem.OnClick = function(sender)
		if Global.symbolMenu then Global.symbolMenu.Visible = not Global.symbolMenu.Visible return end

		getMemoryViewForm().miUserdefinedSymbols.doClick()
		Global.symbolMenu = findFormByName("frmSymbolhandler")
	end
	getMainForm().Menu.Items.add(symbolItem)

	Global.menuExists = true
end

-- 修改签名标签
function modifySignedLabel()
	Global.lblSigned = getMainForm().lblSigned
	if not Global.lblSigned then return end

	local lblSigned = Global.lblSigned
	lblSigned.Caption = "im.ponchine@gmail.com (L-Continue)"
	lblSigned.Font.Color = 0x808080
	lblSigned.Visible = true
end

-- 激活指定记录
function activateRecords()
	if #Config.activeRecords == 0 or Global.activated then return end
	for _, recordID in ipairs(Config.activeRecords) do
		local record = AddressList.getMemoryRecordByID(recordID)
		if record then record.Active = true end
	end
	Global.activated = true
end

-- 初始化函数 - 清除计时器和重置状态
function initializeMonitor()
	-- 读取配置信息
	Config.processName = extractDescAs(301, "S")
	Config.activeRecords = extractDescAs(302, "T") or {}
	Config.checkInterval = extractDescAs(303, "N") or 1000
	Config.checkRequired = extractDescAs(304, "T") or {}
	Config.moduleStableTime = Global.stableTime or extractDescAs(305, "N") or 10000
	Config.enableAutoloading = extractDescAs(306, "B")
	Config.enableExitrestart = extractDescAs(307, "B")
	Config.debugMode = extractDescAs(308, "N") or 2
	if not Config.processName then prints("错误: 未配置进程名称") return end

	prints("=== 读取配置信息 ===")
	readSubRecords(200)
	readSubRecords(300)

	-- 重置状态变量
	prints("=== 全局变量重置 ===")
	if Global.timer then Global.timer.destroy() Global.timer = nil end
	prints("[ 初始化 ] 计时器: %s", Global.timer and "未初始化" or "已销毁")
	Global.processID = 0
	prints("[ 初始化 ] 进程ID: %d", Global.processID)
	Global.attemptNumb = 0
	prints("[ 初始化 ] 尝试次数: %d", Global.attemptNumb)
	Global.isMonitoring = false
	prints("[ 初始化 ] 是否监控中: %s", tostring(Global.isMonitoring))
	Global.processLoaded = false
	prints("[ 初始化 ] 是否加载进程: %s", tostring(Global.processLoaded))
	Global.totalStartTime = getTickCount()
	prints("[ 初始化 ] 运行开始时间: %d", Global.totalStartTime)
	Global.checkStartTime = 0
	prints("[ 初始化 ] 检查开始时间: %s", tostring(Global.checkStartTime))
	Global.checkSpendTime = 0
	prints("[ 初始化 ] 模块持续时间: %s", tostring(Global.checkSpendTime))
	Global.lastModuleNumb = 0
	prints("[ 初始化 ] 最后模块数量: %d", Global.lastModuleNumb)
	Global.lastModuleName = ""
	prints("[ 初始化 ] 最后模块名称: %s", Global.lastModuleName or "未记录")
	Global.loadedModules = {}
	prints("[ 初始化 ] 已加载模块: %s", tostring(Global.loadedModules))
	Global.unloadModules = {}
	prints("[ 初始化 ] 未加载模块: %s", tostring(Global.unloadModules))
end

-- 监控进程状态
function monitorStatus(message, color)
	color = color or 0x0000FF
	prints("[ 状态 ] %s", message)

	local record = AddressList.getMemoryRecordByID(400)
	if not record then return end

	local elapsedTime = getTickCount() - Global.totalStartTime
	local minute = math.floor(elapsedTime / 60000)
	local second = math.floor(elapsedTime / 1000) % 60
	record.Description = string.format("[ %02d:%02d ] %s", minute, second, message)
	record.Color = color
end

-- 进程监控函数
function monitorProcess()
	if not Global.isMonitoring then return end
	-- 计数器
	Global.attemptNumb = Global.attemptNumb + 1

	-- 阶段1: 进程加载检查
	if not Global.processLoaded then
		-- 获取进程ID
		Global.processID = getProcessIDFromProcessName(Config.processName)
		if not Global.processID then monitorStatus(string.format("等待主程序【%s】", Config.processName), 0x0000FF) return end

		-- 尝试附加到进程
		if openProcess(Config.processName) then
			Global.processLoaded = true
			Global.totalStartTime = getTickCount()
			Global.checkStartTime = getTickCount()
			local modules = enumModules(Global.processID)
			Global.lastModuleNumb = #modules
			Global.lastModuleName = modules[#modules] and modules[#modules].Name or ""
			monitorStatus("主程序已加载，检查模块中", 0x0080FF)
		else
			monitorStatus(string.format("游戏加载失败，重试中【%s】", Config.processName), 0x0000FF)
		end
		return
	end

	-- 阶段2: 模块稳定性检查
	local modules = enumModules(Global.processID)
	local currentModuleNumb = #modules

	-- 检查模块数量是否有效
	if currentModuleNumb == 0 then
		Global.totalStartTime = getTickCount()
		Global.processLoaded = false
		monitorStatus("游戏可能退出，重新加载", 0x0000FF)
		return
	end

	-- 检查模块数量是否变化
	local currentModuleName = modules[#modules].Name
	if currentModuleNumb ~= Global.lastModuleNumb or currentModuleName ~= Global.lastModuleName then
		Global.checkStartTime = getTickCount()
		Global.lastModuleNumb = currentModuleNumb
		Global.lastModuleName = currentModuleName
	end

	-- 如果有配置关键模块，检查这些模块是否已加载
	if #Config.checkRequired > 0 then
		local allLoaded = true
		local loadedMap = {}
		for _, module in ipairs(modules) do loadedMap[module.Name] = true end

		Global.loadedModules = {}
		Global.unloadModules = {}

		-- 检查每个关键模块是否已加载
		for _, reqModule in ipairs(Config.checkRequired) do
			if loadedMap[reqModule] then table.insert(Global.loadedModules, reqModule)
			else allLoaded = false table.insert(Global.unloadModules, reqModule) end
		end
		if allLoaded and not Config.enableExitrestart then stopMonitoring() end
	else
		-- 没有配置关键模块，使用稳定时长检查
		Global.checkSpendTime = getTickCount() - Global.checkStartTime
		if Global.checkSpendTime >= Config.moduleStableTime and not Config.enableExitrestart then stopMonitoring() end
	end

	-- 模块稳定性检查（状态信息）
	local isCompleted1 = #Config.checkRequired == 0 and Global.checkSpendTime >= Config.moduleStableTime -- 无关键模块时：时间达标
	local isCompleted2 = #Config.checkRequired > 0 and #Global.loadedModules >= #Config.checkRequired -- 有关键模块时：已加载数量达标
	local isCompleted = isCompleted1 or isCompleted2
	-- 动态生成“模块信息”部分（根据是否完成/是否有关键模块调整内容）
	local moduleInfo = ""
	if not isCompleted then
		-- 未完成时：显示模块数量、最后模块名、进度（时间/关键模块）
		local baseInfo = string.format("模块: %d个, 最后: %s", Global.lastModuleNumb, Global.lastModuleName)
		local progress1 = string.format(" (%.1f/%.1f)", Global.checkSpendTime / 1000, Config.moduleStableTime / 1000)
		local progress2 = string.format(", 关键模块: %d/%d", #Global.loadedModules, #Config.checkRequired)
		moduleInfo = #Config.checkRequired == 0 and baseInfo .. progress1 or baseInfo .. progress2
	else
		-- 完成时的信息
		activateRecords()
		moduleInfo = string.format("模块: %d个, 游戏加载完成! %s退出监测.", Global.lastModuleNumb, Config.enableExitrestart and "已开启" or "未开启")
	end
	monitorStatus(moduleInfo, isCompleted and 0x008000 or 0x0080FF)
end

-- 启动监控
function startMonitoring()
	if Global.isMonitoring then return end

	-- 检查关键内存记录是否存在
	local record = AddressList.getMemoryRecordByID(100)
	if not record then prints("错误: 未找到关键内存记录(ID:100)") return end

	-- 初始化监控数据
	initializeMonitor()

	-- 检查自动加载是否启用
	if not Config.enableAutoloading then monitorStatus("自动加载已禁用", 0x808080) return end

	prints("=== 启动自动加载 ===")
	Global.isMonitoring = true
	Global.timer = createTimer(nil, true)
	Global.timer.Interval = Config.checkInterval
	Global.timer.OnTimer = function()
		local success, err = pcall(monitorProcess)
		if not success then monitorStatus("监控错误: " .. err, 0xFF0000) end
	end
	monitorStatus("开始自动加载游戏")
end

-- 停止监控
function stopMonitoring()
	if not Global.isMonitoring then return end

	Global.isMonitoring = false
	Global.totalStartTime = getTickCount()
	if Global.timer then Global.timer.destroy() Global.timer = nil end
	monitorStatus("监控已停止", 0x808080)
end

-- 增强的符号清理函数
function cleanupSymbols()
	prints("开始彻底清理符号...")

	-- 首先使用内置函数清理
	deleteAllRegisteredSymbols()

	-- 手动检查并清理残留符号
	local symbols = enumRegisteredSymbols()
	if symbols and #symbols > 0 then
		prints("发现 %d 个残留符号，正在手动清理...", #symbols)

		-- 尝试逐个注销符号
		for i, symbol in ipairs(symbols) do
			if symbol.symbolname then
				unregisterSymbol(symbol.symbolname)
				prints("已注销符号: %s", tostring(symbol.symbolname))
			end
		end

		-- 再次检查
		symbols = enumRegisteredSymbols()
		if symbols and #symbols > 0 then
			prints("警告: 仍有 %d 个符号无法清理", #symbols)
		else
			prints("符号清理完成")
		end
	else
		prints("没有发现残留符号")
	end
end


-- 重新加载游戏进程
function reloadProcess()
	-- if Global.isMonitoring then stopMonitoring() end
	-- 禁用所有脚本
	-- local disabled = 0
	-- for i = 2, AddressList.Count - 1 do
	--   local record = AddressList.getMemoryRecord(i)
	--   if record.Active then record.Active = false disabled = disabled + 1 end
	-- end
	-- prints("总共禁用了 %d 个脚本", disabled)

	-- cleanupSymbols()

	-- Global.stableTime = 0
	openProcess(Config.processName)
	-- if Global.processLoaded then openProcess(Config.processName) end
	-- startMonitoring()
	-- Global.stableTime = nil
end

-- 添加额外菜单
addExtraMenu()
-- 执行监控
startMonitoring()
-- 延迟开启紧凑界面
if Global.menuExists then delay(100, function() Global.compactMenu.doClick() end) end
