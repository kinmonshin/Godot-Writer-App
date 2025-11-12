## VersionManager.gd
## 负责创建和管理文件的历史版本（时光机后台）。
## 在每次自动保存前被调用，为文件当前状态创建快照。
extends Node

## 存储所有版本文件的根目录。
const VERSIONS_DIR := "user://versions/"
## 每个独立文件最多保留的历史版本数量。
const MAX_VERSIONS_PER_FILE := 25

func _ready() -> void:
	# 确保版本根目录在启动时就存在
	DirAccess.make_dir_absolute(VERSIONS_DIR)

# ==============================================================================
# --- 公共 API ---
# ==============================================================================

## 为指定文件创建一个版本快照。
## 这是通过复制文件当前内容到一个带时间戳的新文件中实现的。
## @param file_path: String - 原始文件的绝对路径。
func create_version_for(file_path: String) -> void:
	if not FileAccess.file_exists(file_path):
		printerr("VersionManager: Cannot create version. Original file does not exist at: ", file_path)
		return

	# 1. 获取该文件的专属版本目录
	var file_versions_dir := get_versions_dir_for(file_path)
	DirAccess.make_dir_absolute(file_versions_dir)

	# 2. 生成唯一的、基于时间戳的版本文件名
	var timestamp := Time.get_unix_time_from_system()
	var version_file_name := "%d.bak" % timestamp
	var version_file_path := file_versions_dir.path_join(version_file_name)

	# 3. 执行文件复制来创建版本
	var error := DirAccess.copy_absolute(file_path, version_file_path)
	if error == OK:
		print("VersionManager: Created version for %s" % file_path.get_file())
	else:
		printerr("VersionManager: Failed to create version for %s. Error code: %d" % [file_path, error])
		return # 如果复制失败，就不进行后续的清理操作

	# 4. 清理超出数量限制的旧版本
	_prune_old_versions(file_versions_dir)

## 返回指定文件的版本存储目录的绝对路径。
## @param file_path: String - 原始文件的绝对路径。
## @return: String - 该文件的版本目录路径。
func get_versions_dir_for(file_path: String) -> String:
	var file_hash := file_path.md5_text()
	return VERSIONS_DIR.path_join(file_hash)

# ==============================================================================
# --- 内部逻辑 ---
# ==============================================================================

## 清理指定目录中超出数量限制的最旧的版本文件。
func _prune_old_versions(directory_path: String) -> void:
	var packed_files := DirAccess.get_files_at(directory_path)
	
	# [关键修复] 将 PackedStringArray 转换为通用的 Array
	var files := Array(packed_files)
	
	# 现在我们可以安全地使用 filter 了
	files = files.filter(func(file_name): return file_name.ends_with(".bak"))
	
	if files.size() <= MAX_VERSIONS_PER_FILE:
		return

	files.sort()
	
	var files_to_delete_count = files.size() - MAX_VERSIONS_PER_FILE
	print("VersionManager: Pruning %d old version(s)..." % files_to_delete_count)
	
	for i in range(files_to_delete_count):
		var oldest_file := str(files[i])
		var path_to_remove := directory_path.path_join(oldest_file)
		DirAccess.remove_absolute(path_to_remove)
