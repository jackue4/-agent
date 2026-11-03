extends Resource
## Shared, immutable hero definitions. Callers receive detached data for UI/runtime.
const DEFAULT_ID := "chrono"
const IDS := ["chrono","ember","flux"]
const ROSTER := {
	"chrono": {
		"id":"chrono","name":"时隙","codename":"CHRONO / 01","role":"时间控制 · 灵巧生存",
		"desc":"冻结弹幕，再自动锁定附近敌人，在时隙之间连续穿梭。","color":"8deaff","visual":"chrono",
		"primary":{"id":"time_stop","name":"时裂领域","key":"F","cost":40.0,"cooldown":12.0,"duration":3.0,"icon":"time_stop","color":"8deaff","desc":"冻结敌人与敌弹 3 秒，玩家仍能移动和攻击。启动一次 CRT 信号断裂，停滞期间维持冷色滤镜。"},
		"secondary":{"id":"rush","name":"疾影连击","key":"L","cost":35.0,"cooldown":8.0,"duration":.8,"icon":"rush","color":"a9caff","desc":"自动锁定周围最近的可达敌人，0.8 秒内至多五段穿梭，每敌整次至多命中一次。普通段 32、第五段 48 基础伤害，携带攻击祝福；墙与箱罐阻挡突进。"}
	},
	"ember": {
		"id":"ember","name":"烬刃","codename":"EMBER / 02","role":"腾空重击 · 近身爆发",
		"desc":"跃向敌阵，用天坠焰击砸碎防线，再以三重赤焰回旋收尾。","color":"ff9862","visual":"ember",
		"primary":{"id":"sky_slam","name":"天坠焰击","key":"F","cost":40.0,"cooldown":10.0,"duration":.88,"icon":"sky_slam","color":"ffb386","desc":"自动选择 7 米内最近的可达敌人，腾空后于 0.48 秒砸落，对 4.8 米内可见敌人造成 90 基础伤害，携带攻击祝福。无目标时向前跃 4 米；腾空阶段短暂无敌。"},
		"secondary":{"id":"flame_spin","name":"赤焰回旋","key":"L","cost":30.0,"cooldown":9.0,"duration":.5,"icon":"flame_spin","color":"ff704f","desc":"向周围 4.1 米挥出三重回旋斩，每重 22 基础伤害，携带攻击祝福；可击碎补给箱。"}
	},
	"flux": {
		"id":"flux","name":"磁核","codename":"FLUX / 03","role":"引力聚怪 · 弹幕反击",
		"desc":"用奇点聚拢敌人，再以棱镜护卫把敌方火力送回去。","color":"c5a1ff","visual":"flux",
		"primary":{"id":"gravity_well","name":"引力奇点","key":"F","cost":35.0,"cooldown":11.0,"duration":3.0,"icon":"gravity_well","color":"bc8dff","desc":"在前方布置 3 秒引力场，吸引 4.8 米内可见敌人，每 0.6 秒造成 8 基础伤害，结束爆破 55。首领受较小牵引。"},
		"secondary":{"id":"prism_guard","name":"棱镜护卫","key":"L","cost":30.0,"cooldown":12.0,"duration":4.0,"icon":"prism_guard","color":"dfc7ff","desc":"获得 40 临时护盾并持续 4 秒反弹 2.3 米内敌弹；护盾耗尽后仍反弹，到期未用护盾消失。"}
	}
}

static func valid(id: String) -> bool:
	return ROSTER.has(id)

static func get_hero(id: String) -> Dictionary:
	return ROSTER.get(id,ROSTER[DEFAULT_ID]).duplicate(true)

static func all() -> Array:
	var result: Array = []
	for id in IDS: result.append(get_hero(id))
	return result
