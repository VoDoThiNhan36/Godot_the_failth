extends Node

# ============================== PHẦN BUILDING ======================================

# Phân loại CÔNG NĂNG của module (Để biết nó tạo nên khung tàu, hay gắn trên bề mặt)
enum Category {
	STRUCTURAL, # Khung tàu (Prow, Hull, Engine...)
	SURFACE     # Đồ gắn trên bề mặt (Turret, Radar, Solar Panel...)
}

# Phân loại CHÍNH XÁC nó là cái gì
enum ModuleType {
	## Structural
	PROW, HULL, ENGINE, ARMOR, RADIATOR,
	## Weapon
	GUN_TURRET, MISSILE_POD, RAILGUN, LASER, APS
	## Support  
}

enum WeaponFireMode { AUTO, MANUAL }
enum TurretTrackAxis { YAW_ONLY, PITCH_ONLY, YAW_PITCH, FIXED }

# ============================== CÁC PHẦN KHÁC ======================================
