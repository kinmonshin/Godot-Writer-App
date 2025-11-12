extends Control

# ==============================================================================
# --- 常量与枚举 ---
# ==============================================================================
const SAVE_PROGRESS_PATH := "user://progress.cfg"
const SETTINGS_DIALOG_SCENE := preload("res://settings_dialog.tscn")

enum FileMenu { OPEN, SAVE, SAVE_AS, QUIT }
enum SettingsMenu { DISPLAY_SETTINGS }
enum ViewMenu { TOGGLE_DIRECTORY, TOGGLE_BORDERLESS, TOGGLE_FULLSCREEN, TOGGLE_ALWAYS_ON_TOP }


# ==============================================================================
# --- 节点引用 (@onready) ---
# ==============================================================================
@onready var text_edit: TextEdit = %TextEdit
@onready var directory_container: VBoxContainer = %DirectoryContainer
@onready var file_menu: MenuButton = %FileMenu
@onready var view_menu: MenuButton = %ViewMenu
@onready var settings_menu: MenuButton = %SettingsMenu
@onready var file_dialog: FileDialog = %FileDialog
@onready var save_dialog: FileDialog = %SaveDialog
@onready var directory_panel: ScrollContainer = %DirectoryPanel
@onready var margin_container: MarginContainer = %MarginContainer
@onready var menu_bar: MenuBar = %MenuBar
@onready var warning_label: Label = %WarningLabel
@onready var quit_confirm_dialog: Window = %QuitConfirmDialog


# ==============================================================================
# --- 状态变量 ---
# ==============================================================================
var current_file_path := "res://book.txt"
var title_regex := RegEx.new()
var is_modified := false
var settings_dialog_instance: Window # 声明类型
var is_dragging_window := false
var drag_start_offset := Vector2.ZERO
var _was_borderless_before_fullscreen := false


# ==============================================================================
# --- Godot 生命周期函数 ---
# ==============================================================================
func _ready() -> void:
	# 程序的初始化入口
	_initialize_ui_tweaks()
	_initialize_regex()
	_initialize_menus()
	_connect_signals()
	
	# 调用加载函数，而不是零散地调用
	_load_user_data_and_files()

	# 连接主窗口的关闭请求信号
	_setup_window_behavior()
	_sync_view_menu_state()

func _load_user_data_and_files() -> void:
	SettingsManager.load_settings() 
	var scroll_y = load_progress() # 让它返回滚动值
	call_deferred("load_file", current_file_path, scroll_y) # 把滚动值传给 load_file

func _setup_window_behavior() -> void:
	get_tree().auto_accept_quit = false

	# 使用 is_connected() 检查，防止重复连接
	var on_close_requested_callable = Callable(self, "_on_main_window_close_requested")
	if not get_window().is_connected("close_requested", on_close_requested_callable):
		get_window().close_requested.connect(on_close_requested_callable)

func _process(delta: float) -> void:
	# 处理无边框窗口拖动
	if is_dragging_window:
		var mouse_pos_float := Vector2(DisplayServer.mouse_get_position())
		DisplayServer.window_set_position(mouse_pos_float - drag_start_offset)

func _notification(what: int) -> void:
	# 使用 match 语句来处理不同的通知类型
	match what:
		# 当窗口失去焦点时
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			# 保存进度作为一道保险
			save_progress()

# ==============================================================================
# --- 初始化辅助函数 ---
# ==============================================================================
func _initialize_ui_tweaks() -> void:
	margin_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 为菜单栏设置一个最小高度，防止被其他扩展控件完全压缩
	menu_bar.custom_minimum_size.y = 30

func _initialize_regex() -> void:
	# 匹配 "第X章/回/节" 及其后的标题名
	title_regex.compile("^\\s*第.*[章回节].*\\s*$")

func _initialize_menus() -> void:
	# --- 文件菜单 ---
	var file_popup := file_menu.get_popup()
	file_popup.add_item("打开", FileMenu.OPEN)
	file_popup.add_item("保存", FileMenu.SAVE)
	file_popup.add_item("另存为...", FileMenu.SAVE_AS)
	file_popup.add_separator()
	# 注意：即使有分隔符，QUIT 的 ID 依然是 FileMenu.QUIT (值为3)
	file_popup.add_item("退出", FileMenu.QUIT)

	# --- 视图菜单 ---
	var view_popup := view_menu.get_popup()
	# 使用 add_check_item 的第三个参数 id
	view_popup.add_check_item("显示/隐藏目录", ViewMenu.TOGGLE_DIRECTORY)
	view_popup.set_item_checked(0, true) # 索引 0 仍然是目录
	view_popup.add_separator()
	view_popup.add_check_item("无边框模式 (F12)", ViewMenu.TOGGLE_BORDERLESS)
	view_popup.add_check_item("全屏 (F11)", ViewMenu.TOGGLE_FULLSCREEN)
	view_popup.add_check_item("总在最前 (Ctrl+T)", ViewMenu.TOGGLE_ALWAYS_ON_TOP)

	# --- 设置菜单 ---
	var settings_popup := settings_menu.get_popup()
	settings_popup.add_item("显示设置...", SettingsMenu.DISPLAY_SETTINGS)

func _connect_signals() -> void:
	# 核心控件
	text_edit.text_changed.connect(generate_directory)
	text_edit.text_changed.connect(_on_text_changed)
	file_dialog.file_selected.connect(_on_file_selected)
	save_dialog.file_selected.connect(_on_save_dialog_file_selected)

	# UI交互
	menu_bar.gui_input.connect(_on_menu_bar_gui_input)
	
	# 菜单
	file_menu.get_popup().id_pressed.connect(_on_file_menu_id_pressed)
	view_menu.get_popup().id_pressed.connect(_on_view_menu_id_pressed)
	settings_menu.get_popup().id_pressed.connect(_on_settings_menu_id_pressed)

	# 退出确认对话框
	quit_confirm_dialog.close_requested.connect(_on_quit_dialog_canceled)
	%SaveAndQuitButton.pressed.connect(_on_quit_dialog_confirmed)
	%DontSaveAndQuitButton.pressed.connect(_on_quit_dialog_dont_save_pressed)
	%CancelQuitButton.pressed.connect(_on_quit_dialog_canceled)

	# 连接到 SettingsManager 的信号
	SettingsManager.font_size_changed.connect(_on_setting_font_size_changed)
	SettingsManager.text_color_changed.connect(_on_setting_text_color_changed)
	SettingsManager.bg_color_changed.connect(_on_setting_bg_color_changed)


# ==============================================================================
# --- 核心功能与逻辑 ---
# ==============================================================================
func load_file(path: String, target_scroll: int = 0) -> void:
	warning_label.visible = false
	if not FileAccess.file_exists(path):
		text_edit.text = "错误：找不到文件 " + path
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file:
		var content := file.get_as_text()
		
		# 临时断开信号，避免加载文件内容时触发"已修改"状态
		text_edit.text_changed.disconnect(_on_text_changed)
		text_edit.text = content
		text_edit.text_changed.connect(_on_text_changed)
		
		text_edit.clear_undo_history()
		current_file_path = path
		is_modified = false
		update_window_title()

		if " " in content:
			warning_label.text = "警告：文件编码可能不兼容，建议转为UTF-8格式。"
			warning_label.visible = false
		
		generate_directory()

	if target_scroll > 0:
		text_edit.call_deferred("set_v_scroll", target_scroll)

func save_file(path: String) -> void:
	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var err := DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK: return

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(text_edit.text)
		is_modified = false
		update_window_title()

func generate_directory() -> void:
	for child in directory_container.get_children():
		child.queue_free()

	var lines := text_edit.text.split("\n")
	for i in range(lines.size()):
		var line_text := lines[i].strip_edges()
		if _is_title(line_text):
			var button := Button.new()
			button.text = line_text
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.pressed.connect(_on_directory_button_pressed.bind(i))
			directory_container.add_child(button)

func _is_title(line: String) -> bool:
	if line.is_empty(): return false
	if title_regex.search(line): return true
	if line.is_valid_int(): return true
	return false

func update_window_title() -> void:
	var title := current_file_path.get_file()
	if is_modified:
		title += " *"
	DisplayServer.window_set_title(title)

func _scroll_one_page(direction: int) -> void:
	var page_lines := floori(text_edit.get_visible_line_count() * 0.9)
	var current_line := text_edit.get_caret_line()
	var total_lines := text_edit.get_line_count()
	var target_line := clampi(current_line + page_lines * direction, 0, total_lines - 1)
	_on_directory_button_pressed(target_line)

func _scroll_lines(direction: int, num_lines: int = 1) -> void:
	var current_line := text_edit.get_caret_line()
	var total_lines := text_edit.get_line_count()
	var target_line := clampi(current_line + num_lines * direction, 0, total_lines - 1)
	_on_directory_button_pressed(target_line)

func _scroll_view(direction: int, num_lines: int = 3) -> void:
	# 每次滚动3行
	text_edit.scroll_vertical += direction * num_lines


# ==============================================================================
# --- 信号处理函数 (_on_...) ---
# ==============================================================================
func _unhandled_input(event: InputEvent) -> void:
	# 优先处理鼠标滚轮，处理完后立即返回
	if event is InputEventMouseButton:
		if event.is_pressed():
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_view(1)
				get_tree().root.set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_scroll_view(-1)
				get_tree().root.set_input_as_handled()
		return

	# 只处理按下的键盘事件，忽略释放和重复事件
	if not (event is InputEventKey and event.is_pressed() and not event.is_echo()):
		return

	# 将所有自定义动作放在一个字典里，方便管理
	var shortcuts = {
		"open_file": func(): file_dialog.popup_centered(),
		"save_file": func(): save_file(current_file_path),
		"save_file_as": func(): 
			save_dialog.current_path = current_file_path
			save_dialog.popup_centered(),
		"toggle_borderless": func(): _toggle_borderless(),
		"toggle_fullscreen": func(): _toggle_fullscreen(),
		"toggle_always_on_top": func(): _toggle_always_on_top(),
		"ui_page_down": func(): _scroll_one_page(1),
		"ui_page_up": func(): _scroll_one_page(-1),
		"ui_down": func(): _scroll_lines(1),
		"ui_up": func(): _scroll_lines(-1),
	}

	# 遍历所有动作，看是否有匹配的
	for action in shortcuts.keys():
		if Input.is_action_just_pressed(action):
			shortcuts[action].call() # 调用对应的函数
			get_tree().root.set_input_as_handled() # 标记为已处理
			return # 立即返回，不再继续检查

	# 如果循环结束都没有匹配到我们的自定义动作 (如 Ctrl+C)，
	# 就什么都不做，让事件继续传递给 TextEdit 等节点。

func _on_text_changed() -> void:
	if not is_modified:
		is_modified = true
		update_window_title()

func _on_file_selected(path: String) -> void: load_file(path)
func _on_save_dialog_file_selected(new_path: String) -> void:
	save_file(new_path)
	current_file_path = new_path

func _on_directory_button_pressed(line_number: int) -> void:
	text_edit.set_caret_line(line_number, false, true, 0)
	text_edit.center_viewport_to_caret()
	text_edit.grab_focus()

func _on_menu_bar_gui_input(event: InputEvent) -> void:
	if not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS):
		is_dragging_window = false
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		is_dragging_window = event.is_pressed()
		if is_dragging_window:
			drag_start_offset = event.position

# --- 菜单处理 ---
func _on_file_menu_id_pressed(id: int) -> void:
	match id: # 现在 id 就是我们的 FileMenu 枚举值
		FileMenu.OPEN: file_dialog.popup_centered()
		FileMenu.SAVE: save_file(current_file_path)
		FileMenu.SAVE_AS:
			save_dialog.current_path = current_file_path
			save_dialog.popup_centered()
		FileMenu.QUIT: _try_quit()

# [重命名并修改]
func _on_view_menu_id_pressed(id: int) -> void:
	match id: # 现在 id 就是我们的 ViewMenu 枚举值
		ViewMenu.TOGGLE_DIRECTORY:
			directory_panel.visible = not directory_panel.visible
			# 使用 id 来获取 index，更安全
			var item_index = view_menu.get_popup().get_item_index(id)
			view_menu.get_popup().set_item_checked(item_index, directory_panel.visible)
		ViewMenu.TOGGLE_BORDERLESS: _toggle_borderless()
		ViewMenu.TOGGLE_FULLSCREEN: _toggle_fullscreen()
		ViewMenu.TOGGLE_ALWAYS_ON_TOP: _toggle_always_on_top()

# [重命名并修改]
func _on_settings_menu_id_pressed(id: int) -> void:
	if id == SettingsMenu.DISPLAY_SETTINGS:
		_open_settings_dialog()

# --- 设置窗口处理 ---
func _open_settings_dialog() -> void:
	if not is_instance_valid(settings_dialog_instance):
		settings_dialog_instance = SETTINGS_DIALOG_SCENE.instantiate()
		add_child(settings_dialog_instance)
	settings_dialog_instance.popup_centered()

func _on_setting_font_size_changed(new_size: int) -> void:
	text_edit.add_theme_font_size_override("font_size", new_size)

func _on_setting_text_color_changed(new_color: Color) -> void:
	text_edit.add_theme_color_override("font_color", new_color)

func _on_setting_bg_color_changed(new_color: Color) -> void:
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = new_color
	text_edit.add_theme_stylebox_override("normal", stylebox)

func _try_quit() -> void:
	if not is_modified or text_edit.text.is_empty():
		save_progress()
		get_tree().quit()
	else:
		quit_confirm_dialog.popup_centered()

func _on_quit_dialog_confirmed() -> void:
	quit_confirm_dialog.hide()
	save_file(current_file_path)
	save_progress()
	get_tree().quit()

func _on_quit_dialog_dont_save_pressed() -> void:
	quit_confirm_dialog.hide()
	save_progress()
	get_tree().quit()

func _on_quit_dialog_canceled() -> void:
	quit_confirm_dialog.hide()

# 把它放在信号处理函数区域
func _on_main_window_close_requested() -> void:
	# 当用户尝试关闭主窗口时，调用我们的退出决策函数
	_try_quit()

# ==============================================================================
# --- 数据持久化 ---
# ==============================================================================
func save_progress() -> void:
	if not is_instance_valid(text_edit): return
	var config := ConfigFile.new()
	config.set_value("progress", "last_file_path", current_file_path)
	config.set_value("progress", "scroll_y", text_edit.scroll_vertical)
	config.save(SAVE_PROGRESS_PATH)

func load_progress() -> int:
	var config := ConfigFile.new()
	var scroll_y := 0
	if config.load(SAVE_PROGRESS_PATH) == OK:
		current_file_path = config.get_value("progress", "last_file_path", "res://book.txt")
		scroll_y = config.get_value("progress", "scroll_y", 0)
		print("Main: Progress loaded, target scroll_y = ", scroll_y)
	return scroll_y


# ==============================================================================
# --- 窗口管理 ---
# ==============================================================================
func _toggle_borderless() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		return # 全屏下不允许修改无边框

	var new_state = not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, new_state)

	var item_index = view_menu.get_popup().get_item_index(ViewMenu.TOGGLE_BORDERLESS)
	if item_index != -1: # 确保找到了
		view_menu.get_popup().set_item_checked(item_index, new_state)

func _toggle_fullscreen() -> void:
	var current_mode = DisplayServer.window_get_mode()
	var is_fullscreen = (current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN)

	if not is_fullscreen:
		_was_borderless_before_fullscreen = DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, _was_borderless_before_fullscreen)

	var new_state = not is_fullscreen
	var item_index = view_menu.get_popup().get_item_index(ViewMenu.TOGGLE_FULLSCREEN)
	if item_index != -1:
		view_menu.get_popup().set_item_checked(item_index, new_state)

func _toggle_always_on_top() -> void:
	var new_state = not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, new_state)

	var item_index = view_menu.get_popup().get_item_index(ViewMenu.TOGGLE_ALWAYS_ON_TOP)
	if item_index != -1:
		view_menu.get_popup().set_item_checked(item_index, new_state)

# [新增] 启动时同步菜单勾选状态的函数
func _sync_view_menu_state() -> void:
	var popup = view_menu.get_popup()
	var borderless_idx = popup.get_item_index(ViewMenu.TOGGLE_BORDERLESS)
	var fullscreen_idx = popup.get_item_index(ViewMenu.TOGGLE_FULLSCREEN)
	var on_top_idx = popup.get_item_index(ViewMenu.TOGGLE_ALWAYS_ON_TOP)

	if borderless_idx != -1:
		popup.set_item_checked(borderless_idx, DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS))
	if fullscreen_idx != -1:
		popup.set_item_checked(fullscreen_idx, DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	if on_top_idx != -1:
		popup.set_item_checked(on_top_idx, DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP))
