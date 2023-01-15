#include <sourcemod>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define NAME "[CS:S]sm_silenceron"
#define AUTHOR "BallGanda, and help from Addie + rest of discord channel"
#define DESCRIPTION "Weapons that have silencers come with them on"
#define PLUGIN_VERSION "0.0.b1"
#define URL "https://github.com/Ballganda/SourceMod-sm_silenceron"

public Plugin myinfo = {
	name = NAME,
	author = AUTHOR,
	description = DESCRIPTION,
	version = PLUGIN_VERSION,
	url = URL
}

ConVar g_cvEnablePlugin = null;

public void OnPluginStart() {
	
	CheckGameVersion();
		
	CreateConVar("sm_silenceron_version", PLUGIN_VERSION, NAME, FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	g_cvEnablePlugin = CreateConVar("sm_silenceron_enable", "1", "sm_silenceron Enables the plugin <1|0>");
	
	AutoExecConfig(true, "sm_silenceron");
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (!g_cvEnablePlugin.BoolValue) 
	{
        return;
    }

    if (StrEqual(classname, "weapon_m4a1") || StrEqual(classname, "weapon_usp"))
	{
        SDKHook(entity, SDKHook_SpawnPost, OnSpawnPostSilencerOn);
    }
}

void OnSpawnPostSilencerOn(int entity)
{
    SetEntProp(entity, Prop_Send, "m_bSilencerOn", 1);
    SetEntProp(entity, Prop_Send, "m_weaponMode", 1);
}

public void CheckGameVersion()
{
	if(GetEngineVersion() != Engine_CSS)
	{
		SetFailState("Only CS:S Supported");
	}
}
