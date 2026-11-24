name = "Mod Skin Unlocker"
description = [[
由于支持的 Mod 较多，请前往 Mod 发布页查看完整的支持名单。
Due to the large number of supported mods,
please check the Mod release page for the complete list of supported mods.

如果你有任何想要解锁的 Mod 皮肤，请提供工坊 ID 和 Mod 名称。
If you would like skins from another mod to be unlocked,
please provide its Workshop ID and mod name.

本 Mod 为玩家提供免费的皮肤体验。
喜欢相关内容，请支持正版，支持原作者。
This Mod provides players with a free skin experience.
If you enjoy the content,
please support the official releases and the original authors.
]]
author = "local me = nil"
version = "20261026-1"

api_version = 10

priority = 1000

dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false
shipwrecked_compatible = false

all_clients_require_mod = true
client_only_mod = false

server_filter_tags = {
	"MOD_SKIN_UNLOCKER",
}

configuration_options = {
	{
		name = "enable_prism_skin_unlock",
		label = "棱镜 / Prism",
		hover = "启用棱镜皮肤解锁补丁\nEnable the Prism skin unlock patch.",
		options = {
			{ description = "关闭 / Off", data = false },
			{ description = "开启 / On", data = true },
		},
		default = true,
	},
	{
		name = "enable_voidrealm_skin_unlock",
		label = "泰拉 / Void Realm",
		hover = "启用泰拉皮肤解锁补丁\nEnable the Void Realm skin unlock patch.",
		options = {
			{ description = "关闭 / Off", data = false },
			{ description = "开启 / On", data = true },
		},
		default = true,
	},
	{
		name = "enable_dengxian_skin_unlock",
		label = "登仙 / Deng Xian",
		hover = "启用登仙皮肤解锁补丁\nEnable the Deng Xian skin unlock patch.",
		options = {
			{ description = "关闭 / Off", data = false },
			{ description = "开启 / On", data = true },
		},
		default = true,
	},
	{
		name = "enable_hmr_skin_unlock",
		label = "丰耘秘境 / Harvest Mysterious Realm",
		hover = "启用丰耘秘境皮肤解锁补丁\nEnable the Harvest Mysterious Realm skin unlock patch.",
		options = {
			{ description = "关闭 / Off", data = false },
			{ description = "开启 / On", data = true },
		},
		default = true,
	},
	{
		name = "enable_xuaner_skin_unlock",
		label = "璇儿 / Xuaner",
		hover = "启用璇儿皮肤解锁补丁\nEnable the Xuaner skin unlock patch.",
		options = {
			{ description = "关闭 / Off", data = false },
			{ description = "开启 / On", data = true },
		},
		default = true,
	},
	{
		name = "enable_shugo_skin_unlock",
		label = "守护甜心 / Shugo Chara",
		hover = "启用守护甜心皮肤解锁补丁\nEnable the Shugo Chara skin unlock patch.",
		options = {
			{ description = "关闭 / Off", data = false },
			{ description = "开启 / On", data = true },
		},
		default = true,
	},
}
