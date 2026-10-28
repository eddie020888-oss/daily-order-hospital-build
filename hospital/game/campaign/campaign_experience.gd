class_name CampaignExperience
extends RefCounted

# New factories only. Existing saves retain their original earned quotes and wages.
const VERSION:int=1
const INCOME_PERCENT:int=35
const WAGE_PERCENT:int=150

static func enabled(d:Dictionary)->bool:
	return d.get("schema_version",0)==3 and d.get("ruleset","")=="full-hospital-v2" and d.get("campaign",{}).get("experience_version",0) is int and d.campaign.get("experience_version",0)==VERSION

static func initialize(d:Dictionary)->void:
	d.campaign.experience_version=VERSION

static func clinical_income(d:Dictionary,authored_income:int,price_percent:int)->int:
	return int(authored_income*price_percent*(INCOME_PERCENT if enabled(d) else 100)/10000)

static func daily_wage(d:Dictionary,authored_base:int,personal_percent:int=100)->int:
	return ceili(float(authored_base*personal_percent*(WAGE_PERCENT if enabled(d) else 100))/10000.0)

static func validate(d:Dictionary)->String:
	if not d.campaign.has("experience_version"):return ""
	if not enabled(d) or d.campaign.get("people_version",0)!=1 or d.campaign.get("business_version",0)!=1 or d.campaign.get("clinical_decisions_version",0)!=1:return "invalid_experience_version"
	return ""
