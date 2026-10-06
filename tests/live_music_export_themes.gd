extends SceneTree
const Themes := preload("res://scripts/music_theme_catalog.gd")
const Genres := preload("res://scripts/music_genre_catalog.gd")
func _initialize() -> void:
	var data: Dictionary = {}
	var genre_data: Dictionary = {}
	for id: String in Themes.THEMES:
		var settings := Themes.native_settings(id)
		settings.seed=Themes.seed_for(id,12345)
		data[id]=settings
		for genre: String in Genres.GENRES:
			var genre_settings := Themes.native_settings(id,{},genre)
			genre_settings.seed=Themes.seed_for(id,12345)
			genre_data[id+"|"+genre]=genre_settings
	var output := FileAccess.open("res://artifacts/live-music/native-themes.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(data,"\t"))
	output.close()
	output = FileAccess.open("res://artifacts/live-music/native-themes-genres.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(genre_data,"\t"))
	output.close()
	print("EXPORTED 13 DEFAULT + 52 GENRE NATIVE MUSIC THEMES")
	quit()
