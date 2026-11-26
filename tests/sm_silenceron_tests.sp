/**
	sm_silenceron regression tests.

	Load it beside sm_silenceron.smx, then run `sm_silenceron_test` from the server console.
	With `+sm_silenceron_test_autorun 1` it starts 15 s after the map loads and quits the server when done.
	Results go to addons/sourcemod/logs/sm_silenceron_tests.log. A case also fails if SourceMod's
	errors_*.log grew while it ran. Unattended: test.ps1 in the repo root.
*/
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>

#define PLUGIN_VERSION "1.0.0"
#define PLUGIN_FILE "sm_silenceron.smx"
#define NAME_LEN 64
#define STEP_SLOTS 100 // steps per case in a timer value, see Schedule
#define SETTLE 0.5     // seconds a spawned weapon is left before its state is read
#define RELOAD_WAIT 1.5 // seconds after `sm plugins reload` before the reloaded plugin is checked
#define FOREIGN_GRAVITY "300" // a value the config tries to give sv_gravity; must differ from the default 800

enum
{
	C_LOADED = 0,
	C_BOUNDS,
	C_CFG_CREATED,
	C_M4A1_SPAWN,
	C_USP_SPAWN,
	C_OTHER_UNTOUCHED,
	C_DISABLED,
	C_PLAYER_USP,
	C_PLAYER_M4A1,
	C_CFG_APPLIED,
	C_CFG_FOREIGN,
	C_INJECT_ERROR, // fails on purpose with -InjectError; passes otherwise
	NUM_CASES
};

char g_caseNames[NUM_CASES][NAME_LEN];

int g_curCase = -1;
bool g_caseActive;
bool g_running;
int g_pass;
int g_fail;
int g_errSizeAtStart;
int g_origIgnoreWin = -1;
char g_origGravity[16];

int g_weaponRef = INVALID_ENT_REFERENCE;
int g_fakeUid;

char g_logPath[PLATFORM_MAX_PATH];
char g_cfgPath[PLATFORM_MAX_PATH];
ConVar g_cvAutorun;
ConVar g_cvInjectError;

public Plugin myinfo =
{
	name = "sm_silenceron Tests",
	author = "BallGanda",
	description = "Regression tests for sm_silenceron.smx (run sm_silenceron_test on the test server)",
	version = PLUGIN_VERSION,
	url = ""
};

public void OnPluginStart()
{
	BuildPath(Path_SM, g_logPath, sizeof(g_logPath), "logs/sm_silenceron_tests.log");
	BuildPath(Path_SM, g_cfgPath, sizeof(g_cfgPath), "configs/sm_silenceron.cfg");

	strcopy(g_caseNames[C_LOADED], NAME_LEN, "plugin running, cvars exist");
	strcopy(g_caseNames[C_BOUNDS], NAME_LEN, "sm_silenceron_enable is clamped to 0..1");
	strcopy(g_caseNames[C_CFG_CREATED], NAME_LEN, "config file created with the enable entry");
	strcopy(g_caseNames[C_M4A1_SPAWN], NAME_LEN, "spawned weapon_m4a1 has the silencer on");
	strcopy(g_caseNames[C_USP_SPAWN], NAME_LEN, "spawned weapon_usp has the silencer on");
	strcopy(g_caseNames[C_OTHER_UNTOUCHED], NAME_LEN, "spawned weapon_glock keeps weapon mode 0");
	strcopy(g_caseNames[C_DISABLED], NAME_LEN, "enable 0: spawned weapon_m4a1 has the silencer off");
	strcopy(g_caseNames[C_PLAYER_USP], NAME_LEN, "CT spawn USP has the silencer on");
	strcopy(g_caseNames[C_PLAYER_M4A1], NAME_LEN, "M4A1 given to a player has the silencer on");
	strcopy(g_caseNames[C_CFG_APPLIED], NAME_LEN, "config value is applied on load");
	strcopy(g_caseNames[C_CFG_FOREIGN], NAME_LEN, "config line for a foreign cvar is skipped");
	strcopy(g_caseNames[C_INJECT_ERROR], NAME_LEN, "error detection self-check");

	g_cvAutorun = CreateConVar("sm_silenceron_test_autorun", "0", "Run the suite after the map loads, then quit <1|0>", 0, true, 0.0, true, 1.0);
	g_cvInjectError = CreateConVar("sm_silenceron_test_inject_error", "0", "Log a deliberate error so the run must fail <1|0>", 0, true, 0.0, true, 1.0);
	RegServerCmd("sm_silenceron_test", Cmd_RunTests, "Runs the sm_silenceron regression suite");
}

public void OnMapStart()
{
	if (g_cvAutorun.BoolValue && !g_running)
		CreateTimer(15.0, Timer_Autorun, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_Autorun(Handle timer)
{
	Cmd_RunTests(0);
	return Plugin_Stop;
}

public void OnPluginEnd()
{
	Cleanup();
	RestoreCvars();
}

public Action Cmd_RunTests(int args)
{
	if (g_running)
	{
		PrintToServer("[sm_silenceron_test] already running");
		return Plugin_Handled;
	}
	if (FindPluginByFile(PLUGIN_FILE) == null)
	{
		LogToFileEx(g_logPath, "=== sm_silenceron tests aborted: %s is not loaded ===", PLUGIN_FILE);
		return Plugin_Handled;
	}

	// A fake client joining or leaving would otherwise end the round and respawn players under a case.
	ConVar ignore = FindConVar("mp_ignore_round_win_conditions");
	g_origIgnoreWin = ignore.IntValue;
	ignore.IntValue = 1;
	FindConVar("sv_gravity").GetString(g_origGravity, sizeof(g_origGravity));

	g_running = true;
	g_pass = 0;
	g_fail = 0;
	LogToFileEx(g_logPath, "=== sm_silenceron tests started (%d cases) ===", NUM_CASES);
	StartCase(0);
	return Plugin_Handled;
}

//===== Cases =====

void StartCase(int c)
{
	g_curCase = c;
	g_caseActive = true;
	g_errSizeAtStart = ErrorLogSize();
	RunStep(c, 1);
}

void RunStep(int c, int step)
{
	char why[192];
	switch (c)
	{
		case C_LOADED:
		{
			Handle plugin = FindPluginByFile(PLUGIN_FILE);
			bool ok = GetPluginStatus(plugin) == Plugin_Running
				&& FindConVar("sm_silenceron_version") != null
				&& FindConVar("sm_silenceron_enable") != null;
			EndCase(ok, ok ? "running" : "plugin not running or a cvar is missing");
		}
		case C_BOUNDS:
		{
			ConVar enable = FindConVar("sm_silenceron_enable");
			enable.SetString("5");
			int high = enable.IntValue;
			enable.SetString("-3");
			int low = enable.IntValue;
			enable.SetString("1");
			Format(why, sizeof(why), "5 -> %d, -3 -> %d", high, low);
			EndCase(high == 1 && low == 0, why);
		}
		case C_CFG_CREATED:
		{
			char text[4096];
			bool read = ReadCfg(text, sizeof(text));
			EndCase(read && StrContains(text, "sm_silenceron_enable \"1\"") != -1,
				read ? "file holds sm_silenceron_enable \"1\"" : "file missing or unreadable");
		}
		case C_M4A1_SPAWN: SpawnCase(step, "weapon_m4a1", 1, 1);
		case C_USP_SPAWN: SpawnCase(step, "weapon_usp", 1, 1);
		case C_OTHER_UNTOUCHED: SpawnCase(step, "weapon_glock", -1, 0);
		case C_DISABLED:
		{
			if (step == 1)
				FindConVar("sm_silenceron_enable").SetString("0");
			SpawnCase(step, "weapon_m4a1", 0, 0);
		}
		case C_PLAYER_USP:
		{
			if (step == 1)
			{
				if (!SpawnFakeCT())
					return;
				Schedule(1.0, c, 2);
				return;
			}
			int client = GetClientOfUserId(g_fakeUid);
			int weapon = client ? GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY) : -1;
			CheckWeapon(weapon, "weapon_usp", 1, 1);
		}
		case C_PLAYER_M4A1:
		{
			if (step == 1)
			{
				if (!SpawnFakeCT())
					return;
				Schedule(1.0, c, 2);
				return;
			}
			int client = GetClientOfUserId(g_fakeUid);
			if (step == 2)
			{
				if (client == 0)
				{
					EndCase(false, "fake client is gone");
					return;
				}
				GivePlayerItem(client, "weapon_m4a1");
				FakeClientCommand(client, "use weapon_m4a1");
				Schedule(1.5, c, 3); // the rifle deploys in hand
				return;
			}
			int weapon = client ? GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY) : -1;
			CheckWeapon(weapon, "weapon_m4a1", 1, 1);
		}
		case C_CFG_APPLIED:
		{
			if (step == 1)
			{
				FindConVar("sm_silenceron_enable").SetString("1");
				WriteCfg("sm_silenceron_enable \"0\"\n");
				ServerCommand("sm plugins reload sm_silenceron");
				Schedule(RELOAD_WAIT, c, 2);
				return;
			}
			int value = FindConVar("sm_silenceron_enable").IntValue;
			Format(why, sizeof(why), "sm_silenceron_enable is %d after reload", value);
			EndCase(value == 0, why);
		}
		case C_CFG_FOREIGN:
		{
			if (step == 1)
			{
				char text[128];
				Format(text, sizeof(text), "sv_gravity %s\nsm_silenceron_enable 1\n", FOREIGN_GRAVITY);
				WriteCfg(text);
				ServerCommand("sm plugins reload sm_silenceron");
				Schedule(RELOAD_WAIT, c, 2);
				return;
			}
			char gravity[16];
			FindConVar("sv_gravity").GetString(gravity, sizeof(gravity));
			int enable = FindConVar("sm_silenceron_enable").IntValue;
			bool ok = !StrEqual(gravity, FOREIGN_GRAVITY) && enable == 1;
			Format(why, sizeof(why), "sv_gravity %s, sm_silenceron_enable %d", gravity, enable);
			EndCase(ok, why);
		}
		case C_INJECT_ERROR:
		{
			if (g_cvInjectError.BoolValue)
				LogError("deliberate error from sm_silenceron_test_inject_error");
			EndCase(true, g_cvInjectError.BoolValue ? "error logged on purpose" : "no error injected");
		}
	}
}

// Step 1 spawns a loose weapon; step 2 checks it. silencer -1 means the weapon has no silencer to check.
void SpawnCase(int step, const char[] classname, int silencer, int mode)
{
	if (step == 1)
	{
		int weapon = CreateEntityByName(classname);
		if (weapon == -1 || !DispatchSpawn(weapon))
		{
			EndCase(false, "could not spawn the weapon");
			return;
		}
		g_weaponRef = EntIndexToEntRef(weapon);
		Schedule(SETTLE, g_curCase, 2);
		return;
	}
	CheckWeapon(EntRefToEntIndex(g_weaponRef), classname, silencer, mode);
}

void CheckWeapon(int weapon, const char[] classname, int silencer, int mode)
{
	char found[64], why[192];
	if (weapon <= 0 || !IsValidEntity(weapon))
	{
		EndCase(false, "weapon is gone");
		return;
	}
	GetEntityClassname(weapon, found, sizeof(found));
	if (!StrEqual(found, classname))
	{
		Format(why, sizeof(why), "expected %s, found %s", classname, found);
		EndCase(false, why);
		return;
	}
	int gotMode = GetEntProp(weapon, Prop_Send, "m_weaponMode");
	if (silencer == -1)
	{
		Format(why, sizeof(why), "m_weaponMode %d", gotMode);
		EndCase(gotMode == mode, why);
		return;
	}
	int gotSilencer = GetEntProp(weapon, Prop_Send, "m_bSilencerOn");
	Format(why, sizeof(why), "m_bSilencerOn %d, m_weaponMode %d", gotSilencer, gotMode);
	EndCase(gotSilencer == silencer && gotMode == mode, why);
}

bool SpawnFakeCT()
{
	int client = CreateFakeClient("SilencerTest");
	if (client == 0)
	{
		EndCase(false, "could not create a fake client");
		return false;
	}
	g_fakeUid = GetClientUserId(client);
	ChangeClientTeam(client, CS_TEAM_CT);
	CS_RespawnPlayer(client);
	return true;
}

//===== Case control =====

void EndCase(bool ok, const char[] msg)
{
	if (!g_caseActive)
		return;

	char line[256];
	if (ErrorLogSize() > g_errSizeAtStart)
	{
		ok = false;
		Format(line, sizeof(line), "[FAIL] %s - SourceMod logged errors during this case (see logs/errors_*.log)", g_caseNames[g_curCase]);
	}
	else
		Format(line, sizeof(line), "[%s] %s - %s", ok ? "PASS" : "FAIL", g_caseNames[g_curCase], msg);
	LogToFileEx(g_logPath, "%s", line);
	PrintToServer("%s", line);
	if (ok) g_pass++; else g_fail++;

	g_caseActive = false;
	Cleanup();
	CreateTimer(0.5, Timer_NextCase, g_curCase + 1, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_NextCase(Handle timer, any next)
{
	int n = view_as<int>(next);
	if (n < NUM_CASES)
	{
		StartCase(n);
		return Plugin_Stop;
	}

	g_running = false;
	RestoreCvars();
	DeleteFile(g_cfgPath); // leave no edited config behind for the next run
	if (GetPluginStatus(FindPluginByFile(PLUGIN_FILE)) != Plugin_Running)
	{
		g_fail++;
		LogToFileEx(g_logPath, "[FAIL] %s is no longer running at the end of the suite", PLUGIN_FILE);
	}
	LogToFileEx(g_logPath, "tests finished: %d passed, %d failed", g_pass, g_fail);
	if (g_cvAutorun.BoolValue)
	{
		ServerCommand("sm plugins list");
		ServerCommand("sm exts list");
		CreateTimer(1.0, Timer_Quit);
	}
	return Plugin_Stop;
}

public Action Timer_Quit(Handle timer)
{
	ServerCommand("quit");
	return Plugin_Stop;
}

void Schedule(float delay, int c, int step)
{
	CreateTimer(delay, Timer_Step, c * STEP_SLOTS + step, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_Step(Handle timer, any data)
{
	int c = view_as<int>(data) / STEP_SLOTS;
	if (g_caseActive && c == g_curCase) // a step of a case that already ended is ignored
		RunStep(c, view_as<int>(data) % STEP_SLOTS);
	return Plugin_Stop;
}

//===== Helpers =====

void Cleanup()
{
	int weapon = EntRefToEntIndex(g_weaponRef);
	if (weapon > 0)
		AcceptEntityInput(weapon, "Kill");
	g_weaponRef = INVALID_ENT_REFERENCE;

	int client = GetClientOfUserId(g_fakeUid);
	if (client != 0)
		KickClient(client, "sm_silenceron test done");
	g_fakeUid = 0;

	if (g_running)
		FindConVar("sm_silenceron_enable").SetString("1");
}

void RestoreCvars()
{
	if (g_origIgnoreWin != -1)
	{
		FindConVar("mp_ignore_round_win_conditions").IntValue = g_origIgnoreWin;
		g_origIgnoreWin = -1;
	}
	if (g_origGravity[0] != '\0')
	{
		FindConVar("sv_gravity").SetString(g_origGravity);
		g_origGravity[0] = '\0';
	}
	ConVar enable = FindConVar("sm_silenceron_enable");
	if (enable != null)
		enable.SetString("1");
}

// Size of today's SourceMod error log; it grows whenever any plugin throws.
int ErrorLogSize()
{
	char date[16], path[PLATFORM_MAX_PATH];
	FormatTime(date, sizeof(date), "%Y%m%d");
	BuildPath(Path_SM, path, sizeof(path), "logs/errors_%s.log", date);
	return FileExists(path) ? FileSize(path) : 0;
}

bool ReadCfg(char[] text, int maxlen)
{
	text[0] = '\0';
	File f = OpenFile(g_cfgPath, "rb");
	if (f == null)
		return false;
	int len = f.ReadString(text, maxlen, maxlen - 1);
	delete f;
	if (len < 0)
		return false;
	text[len] = '\0';
	return true;
}

void WriteCfg(const char[] text)
{
	File f = OpenFile(g_cfgPath, "wb");
	if (f == null)
	{
		LogError("cannot write %s", g_cfgPath);
		return;
	}
	f.WriteString(text, false);
	delete f;
}
