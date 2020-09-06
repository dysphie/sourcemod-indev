/**
 * TODO: 
 * - group scattered item data into Medical-indexed ItemData array
 * - cleanup
 * - opti?
 */

#include <sdktools>
#include <sdkhooks>
#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
    name        = "[NMRiH] Team Healing",
    author      = "Dysphie",
    description = "Allow use of first aid kits and bandages on teammates",
    version     = "0.1.0",
    url         = ""
};

#define MAXPLAYERS_NMRIH 9


enum MedicalSequence
{
	MedicalSequence_Idle = 4,
	MedicalSequence_WalkIdle = 7
}

enum VoiceCommand
{
	VoiceCommand_Stay = 4,
	VoiceCommand_ThankYou = 5
}

enum Medical
{
	Medical_None = -1,
	Medical_FirstAidKit,
	Medical_Bandages
}

enum struct SoundMap
{
	ArrayList keys;
	ArrayList sounds;

	void Init()
	{
		this.keys = new ArrayList();
		this.sounds = new ArrayList(32);
	}

	void Set(int key, const char[] sound)
	{
		this.keys.Push(key);
		this.sounds.PushString(sound);
	}
}

SoundMap sfx[2];

enum struct HealProgress
{
	int client;
	int target;
	Medical medical;
	float startTime;
	float duration;

	int cursor;

	void Think(int& target, Medical& medical)
	{
		if (this.IsActive())
		{
			if (target != this.target || medical != this.medical)
			{
				this.Stop();
				return;
			}

			float curTime = GetGameTime();

			// Play sounds
			float elapsedPct = (curTime - this.startTime) / this.duration * 100;

			int max = sfx[this.medical].keys.Length;
			for (; this.cursor < max; this.cursor++)
			{
				int playAtPct = sfx[this.medical].keys.Get(this.cursor);

				// Bail if we've exhausted the sounds to play this frame
				if (elapsedPct < playAtPct)
					break;

				char sound[32]; //TODO move out of loop
				sfx[this.medical].sounds.GetString(this.cursor, sound, sizeof(sound));
				EmitMedicalSound(this.client, sound);
			}
		
			if (curTime >= this.startTime + this.duration)
			{
				this.Complete();
				return;
			}
		}
		else
		{
			if (target != -1 && medical != Medical_None)
				this.Start(target, medical);
		}
	}

	void Start(int& target, Medical& medical)
	{
		this.target = target;
		this.medical = medical;
		this.startTime = GetGameTime();
		this.duration = GetDurationForMedical(medical);

		FreezePlayer(this.client);
		ShowProgressBar(this.client, this.duration);
		TryVoiceCommand(this.client, VoiceCommand_Stay);
	}

	void Complete()
	{
		TryVoiceCommand(this.target, VoiceCommand_ThankYou);
		DoFunctionForMedical(this.medical, this.target);

		int item = GetEntPropEnt(this.client, Prop_Send, "m_hActiveWeapon");
		SDKHooks_DropWeapon(this.client, item);
		RemoveEntity(item);

		this.Stop();
	}

	void Stop()
	{
		PrintCenterText(this.client, "");
		UnfreezePlayer(this.client);
		HideProgressBar(this.client);
		this.Reset();
	}

	void Init(int client)
	{
		this.client = client;
		this.Reset();
	}

	void Reset()
	{
		this.cursor = 0;
		this.target = -1;
		this.startTime = -1.0;
		this.duration = -1.0;
		this.medical = Medical_None;
	}

	bool IsActive()
	{
		return this.startTime != -1.0;
	}
}

HealProgress heal[MAXPLAYERS_NMRIH+1];
float nextThink[MAXPLAYERS_NMRIH+1];
ConVar medkitTime;
ConVar bandageTime;

public void OnPluginStart()
{
	medkitTime = CreateConVar("sm_team_heal_medkit_time", "8.1");
	bandageTime = CreateConVar("sm_team_heal_bandage_time", "2.8");

	for (int i = 1; i <= MaxClients; i++)
		heal[i].Init(i);

	SoundMap medkitSnd;
	medkitSnd.Init();
	medkitSnd.Set(0, "Medkit.Open");
	medkitSnd.Set(8, "MedPills.Draw");
	medkitSnd.Set(13, "MedPills.Open");
	medkitSnd.Set(17, "MedPills.Shake");
	medkitSnd.Set(19, "MedPills.Shake");
	medkitSnd.Set(30, "Medkit.Shuffle");
	medkitSnd.Set(39, "Stitch.Prepare");
	medkitSnd.Set(46, "Stitch.Flesh");
	medkitSnd.Set(49, "Weapon_db.GenericFoley");
	medkitSnd.Set(52, "Stitch.Flesh");
	medkitSnd.Set(55, "Stitch.Flesh");
	medkitSnd.Set(58, "Medkit.Shuffle");
	medkitSnd.Set(66, "Scissors.Snip");
	medkitSnd.Set(67, "Scissors.Snip");
	medkitSnd.Set(75, "Scissors.Snip");
	medkitSnd.Set(78, "Weapon_db.GenericFoley");
	medkitSnd.Set(79, "Medkit.Shuffle");
	medkitSnd.Set(84, "Weapon_db.GenericFoley");
	medkitSnd.Set(90, "Weapon_db.GenericFoley");
	medkitSnd.Set(94, "Tape.unravel");

	SoundMap bandageSnd;
	bandageSnd.Init();
	bandageSnd.Set(0, "Weapon_db.GenericFoley");
	bandageSnd.Set(41, "Bandage.Unravel1");
	bandageSnd.Set(55, "Bandage.Unravel2");
	bandageSnd.Set(80, "Bandage.Apply");

	sfx[Medical_FirstAidKit] = medkitSnd;
	sfx[Medical_Bandages] = bandageSnd;
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], 
	int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	if (!IsPlayerAlive(client))
		return Plugin_Continue;

	float curTime = GetGameTime();

	if (curTime < nextThink[client])
		return Plugin_Continue;

	int target = -1;
	Medical medical = Medical_None;

	for(;;) // Compiler doesn't like while(1)
	{
		if ( !(buttons & IN_USE) )
			break;

		int item = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if (item == -1)
			break;

		if ((medical = GetMedicalDefinition(item)) == Medical_None)
			break;

		int new_target = GetClientAimTarget(client, .only_clients=true);
		if (new_target == -1)
			break;

		if (!TestPreCondForMedical(medical, item, new_target))
			break;

		float self_pos[3];
		float target_pos[3];

		GetClientAbsOrigin(client, self_pos);
		GetClientAbsOrigin(new_target, target_pos);

		if (GetVectorDistance(self_pos, target_pos) > 100.0)
			break;

		target = new_target;
		break;
	}

	heal[client].Think(target, medical);
	nextThink[client] = curTime + 0.1;

	return Plugin_Continue;
}

bool TestPreCondForMedical(Medical& medical, int& item, int& target)
{
	switch (medical)
	{
		case Medical_Bandages:
		{
			if (!IsPlayerBleeding(target))
				return false;

			any s = GetEntProp(item, Prop_Send, "m_nSequence");
			return s == MedicalSequence_Idle || s == MedicalSequence_WalkIdle;
		}

		case Medical_FirstAidKit:
		{
			if (!IsPlayerHurt(target))
				return false;

			any s = GetEntProp(item, Prop_Send, "m_nSequence");
			return s == MedicalSequence_Idle || s == MedicalSequence_WalkIdle;
		}
		
		default:
			return false;
	}
}

void DoFunctionForMedical(Medical& medical, int& target)
{
	switch (medical)
	{
		case Medical_Bandages:
			ApplyBandage(target);

		case Medical_FirstAidKit:
			ApplyFirstAidKit(target);
	}	
}

float GetDurationForMedical(Medical& medical)
{
	switch (medical)
	{
		case Medical_Bandages:
			return bandageTime.FloatValue;

		case Medical_FirstAidKit:
			return medkitTime.FloatValue;

		default:
			return -1.0;
	}
}

// TODO: stringmap?
Medical GetMedicalDefinition(int item)
{
	char classname[32];
	GetEntityClassname(item, classname, sizeof(classname));

	if (strcmp(classname[5], "first_aid") == 0)
		return Medical_FirstAidKit;
	
	if (strcmp(classname[5], "bandages") == 0)
		return Medical_Bandages;
	
	return Medical_None;
}

stock bool IsPlayerHurt(int client)
{
	return GetClientHealth(client) < GetEntProp(client, Prop_Data, "m_iMaxHealth");
}

stock bool IsPlayerBleeding(int client)
{
	return !!GetEntProp(client, Prop_Send, "_bleedingOut");
}

stock void ShowProgressBar(int client, float duration, float prefill = 0.0)
{
	BfWrite bf = UserMessageToBfWrite(StartMessageOne("ProgressBarShow", client));
	bf.WriteFloat(duration);
	bf.WriteFloat(prefill);
	EndMessage();
}

stock void HideProgressBar(int client)
{
	StartMessageOne("ProgressBarHide", client);
	EndMessage();
}

stock void FreezePlayer(int client)
{
	int curFlags = GetEntProp(client, Prop_Send, "m_fFlags");
	SetEntProp(client, Prop_Send, "m_fFlags", curFlags | 128);
}

stock void UnfreezePlayer(int client)
{
	int curFlags = GetEntProp(client, Prop_Send, "m_fFlags");
	SetEntProp(client, Prop_Send, "m_fFlags", curFlags & ~128);
}

void TryVoiceCommand(int client, VoiceCommand voice)
{
	static float lastVoiceTime[MAXPLAYERS_NMRIH+1];

	static ConVar hVoiceCooldown;
	if (!hVoiceCooldown)
		hVoiceCooldown = FindConVar("sv_voice_cooldown");

	float curTime = GetGameTime();
	if (curTime - hVoiceCooldown.FloatValue < lastVoiceTime[client])
	{
		return;
	}

	lastVoiceTime[client] = curTime;
	float origin[3];
	GetClientAbsOrigin(client, origin);

	TE_Start("TEVoiceCommand");
	TE_WriteNum("_playerIndex", client);
	TE_WriteNum("_voiceCommand", _:voice);
	TE_SendToAllInRange(origin, RangeType_Audibility);
}

void ApplyBandage(int client)
{
	static ConVar hBandageHealAmt;
	if (!hBandageHealAmt)
		hBandageHealAmt = FindConVar("sv_bandage_heal_amt");

	if (GetEntProp(client, Prop_Send, "_bleedingOut"))
		SetEntProp(client, Prop_Send, "_bleedingOut", 0);

	int newHealth = GetClientHealth(client) + hBandageHealAmt.IntValue;
	int maxHealth = GetEntProp(client, Prop_Data, "m_iMaxHealth");
	if (newHealth > maxHealth)
		newHealth = maxHealth;

	SetEntityHealth(client, newHealth);
}

void ApplyFirstAidKit(int client)
{
	static ConVar hFirstAidHealAmt;
	if (!hFirstAidHealAmt)
		hFirstAidHealAmt = FindConVar("sv_first_aid_heal_amt");

	if (GetEntProp(client, Prop_Send, "_bleedingOut"))
		SetEntProp(client, Prop_Send, "_bleedingOut", 0);

	int newHealth = GetClientHealth(client) + hFirstAidHealAmt.IntValue;
	int maxHealth = GetEntProp(client, Prop_Data, "m_iMaxHealth");
	if (newHealth > maxHealth)
		newHealth = maxHealth;

	SetEntityHealth(client, newHealth);
}

void EmitMedicalSound(int client, const char[] game_sound)
{
	int entity;
	char sound_name[128];
	int channel = SNDCHAN_AUTO;
	int sound_level = SNDLEVEL_NORMAL;
	float volume = SNDVOL_NORMAL;
	int pitch = SNDPITCH_NORMAL;
	GetGameSoundParams(game_sound, channel, sound_level, volume, pitch, sound_name, sizeof(sound_name), entity);

	// Play sound.
	EmitSoundToAll(sound_name, client, channel, sound_level, SND_CHANGEVOL | SND_CHANGEPITCH, volume, pitch);
}
