
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define MAXPLAYERS_NMRIH 9

public Plugin myinfo = {
    name        = "[NMRiH] Team Healing",
    author      = "Dysphie",
    description = "Allow use of first aid kits and bandages on teammates",
    version     = "0.2.0",
    url         = ""
};

ConVar medkitTime;
ConVar bandageTime;
ConVar useDistance;
ConVar healCooldown;
ConVar thinkInterval;


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
int healer[MAXPLAYERS_NMRIH+1] = {-1, ...};

enum MedicalSequence
{
	MedicalSequence_Run = 3,
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

enum struct HealingUse
{
	int client;
	int target;
	float startTime;
	float duration;
	float canTryHealTime;
	float startAngles[3];
	Handle think;
	int sndCursor; // Sfx 
	Medical medical;

	bool IsActive()
	{
		return this.startTime != -1.0;
	}

	void Start(int target, Medical medical)
	{
		this.duration = GetMedicalDuration(medical);
		if (this.duration == -1)
			return;

		this.target = target;
		this.medical = medical;
		this.startTime = GetGameTime();
		healer[target] = this.client;

		GetClientAbsAngles(this.client, this.startAngles);

		FreezePlayer(this.client);
		FreezePlayer(this.target);

		// TODO: Group these into a single UserMsg?
		ShowProgressBar(this.client, this.duration);
		ShowProgressBar(target, this.duration);

		// TODO: Some voice lines don't really fit here
		TryVoiceCommand(this.client, VoiceCommand_Stay);

		// EnterThirdPerson(this.client, this.target);
		// EnterThirdPerson(this.target, this.client);

		// Use outsider func because CreateTimer won't let us call our own methods
		this.think = CreateTimer(thinkInterval.FloatValue, _ThinkHelper, this.client, TIMER_REPEAT);
	}

	void UseThink()
	{
		if (!IsPlayerAlive(this.client) || !IsPlayerAlive(this.target))
		{
			this.Stop();
			return;
		}

		// Player rotated too much
		float angles[3];
		GetClientAbsAngles(this.client, angles);
		if (GetDifferenceBetweenAngles(angles, this.startAngles) > 90.0)
		{
			this.Stop();
			return;
		}

		if (!(GetClientButtons(this.client) & IN_USE))
		{
			this.Stop();
			return;
		}

		Medical medical = GetActiveMedical(this.client);
		if (medical != this.medical)
		{
			this.Stop();
			return;
		}

		if (!CanPlayerUseMedical(this.target, this.medical))
		{
			this.Stop();
			return;	
		}

		// Show hud text
		PrintCenterText(this.target, "Being healed by %N. Crouch to cancel", this.client);
		PrintCenterText(this.client, "Healing %N", this.target);


		float curTime = GetGameTime();

		// Play sounds
		char sound[32]; 
		float elapsedPct = (curTime - this.startTime) / this.duration * 100;

		int max = sfx[this.medical].keys.Length;
		for (; this.sndCursor < max; this.sndCursor++)
		{
			int playAtPct = sfx[this.medical].keys.Get(this.sndCursor);

			// Bail if we've exhausted the sounds to play this frame
			if (elapsedPct < playAtPct)
				break;

			sfx[this.medical].sounds.GetString(this.sndCursor, sound, sizeof(sound));
			EmitMedicalSound(this.client, sound);
		}

		// Check target distance more leniently in case either player slid a bit
		// Currently healee could walk away using suicide double-tap glitch

		float clientPos[3];
		float targetPos[3];

		GetClientAbsOrigin(this.client, clientPos);
		GetClientAbsOrigin(this.target, targetPos);

		if (GetVectorDistance(clientPos, targetPos) > useDistance.FloatValue + 30.0)
		{
			this.Stop();
			return;
		}

		if (curTime >= this.startTime + this.duration)
		{
			this.Succeed();
			return;
		}
	}

	void Succeed()
	{
		DoFunctionForMedical(this.medical, this.target);

		// A little courtesy goes a long way!
		TryVoiceCommand(this.target, VoiceCommand_ThankYou);

		// Active weapon should always be our medical
		// TODO: Maybe iterate m_hMyWeapons instead for safety?
		int item = GetEntPropEnt(this.client, Prop_Send, "m_hActiveWeapon");
		if (item != -1)
		{
			SDKHooks_DropWeapon(this.client, item);
			RemoveEntity(item);
		}

		this.Stop();
	}

	void Stop(bool success = false)
	{
		if (!this.IsActive())
			return;

		healer[this.target] = -1;
		this.think = null;

		// Stop 
		PrintCenterText(this.client, "");
		PrintCenterText(this.client, "");

		UnfreezePlayer(this.client);
		UnfreezePlayer(this.target);

		// If we didn't make it the whole way we need to
		// cancel the progress bars
		if (!success)
		{	
			HideProgressBar(this.client);
			HideProgressBar(this.target);	
		}

		// ExitThirdPerson(this.client);
		// ExitThirdPerson(this.target);

		this.canTryHealTime = GetGameTime() + healCooldown.FloatValue;

		this.Reset();
	}

	void Init(int client)
	{
		this.client = client;
		this.Reset();
	}

	void Reset()
	{
		this.target = -1;
		this.startTime = -1.0;
		this.duration = -1.0;
		this.medical = Medical_None;
		this.sndCursor = 0;
	}

}

HealingUse healing[MAXPLAYERS_NMRIH+1];

public Action _ThinkHelper(Handle timer, int index)
{
	if (!healing[index].IsActive())
		return Plugin_Stop;

	healing[index].UseThink();

	return Plugin_Continue;
}

public void OnPluginStart()
{
	medkitTime = CreateConVar("sm_team_heal_medkit_time", "8.1");
	bandageTime = CreateConVar("sm_team_heal_bandage_time", "2.8");
	healCooldown = CreateConVar("sm_team_heal_cooldown", "5.0");
	useDistance = CreateConVar("sm_team_heal_use_distance", "50.0");
	thinkInterval = CreateConVar("sm_team_heal_think_interval", "0.1");

	for (int i = 1; i <= MaxClients; i++)
		healing[i].Init(i);

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

	// RegConsoleCmd("sm_unstuck", OnCmdUnstuck);
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

public Action OnCmdUnstuck(int client, int args)
{
	for (int i= 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			UnfreezePlayer(i);
}

public void OnClientDisconnect(int client)
{
	if (healing[client].IsActive())
		healing[client].Stop();
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], 
	const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if (buttons & IN_DUCK && healer[client] != -1)
		healing[healer[client]].Stop();

	// Can't start heal if we are already healing
	if (healing[client].IsActive())
		return;

	// Not holding use
	if (!(GetEntProp(client, Prop_Data, "m_afButtonPressed") & IN_USE))
		return;

	// Not holding a medical item / medical not ready
	Medical medical = GetActiveMedical(client);
	if (medical == Medical_None)
		return;

	// Not aiming at another player / player out of reach
	int target = GetClientUseTarget(client);
	if (target == -1)
		return;

	// TODO: Zombies are too close
	// Do this so target has time to break free if they wish

	// Target doesn't need/want medical
	if (!CanPlayerUseMedical(target, medical))
	{
		PrintCenterText(client, "Player is healthy");
		return;
	}

	float curTime = GetGameTime();

	// Someone rejected our heal and we are on cooldown

	if (healing[client].canTryHealTime > curTime)
	{
		PrintCenterText(client, "Cooldown. Try again in %d seconds", RoundToCeil(healing[client].canTryHealTime - curTime));
		return;
	}

	// Okay we can heal
	healing[client].Start(target, medical);
}

int GetClientUseTarget(int client)
{
	float hullAng[3];
	GetClientEyeAngles(client, hullAng);

	float hullStart[3];
	GetClientEyePosition(client, hullStart);

	float hullEnd[3];
	ForwardVector(hullStart, hullAng, useDistance.FloatValue, hullEnd);

	float hullMins[3] = { -20.0, -20.0, -20.0 };
	float hullMaxs[3] = {  20.0,  20.0,  20.0 };

	TR_TraceHullFilter(hullStart, hullEnd, hullMins, hullMaxs, MASK_PLAYERSOLID, TR_OtherPlayers, client);

	int entity = TR_GetEntityIndex();
	return (entity > 0) ? entity : -1;
}

bool TR_OtherPlayers(int entity, int mask, int client)
{
	return entity != client && entity <= MaxClients;
}

void ForwardVector(const float vPos[3], const float vAng[3], float fDistance, float vReturn[3])
{
	float vDir[3];
	GetAngleVectors(vAng, vDir, NULL_VECTOR, NULL_VECTOR);
	vReturn = vPos;
	vReturn[0] += vDir[0] * fDistance;
	vReturn[1] += vDir[1] * fDistance;
	vReturn[2] += vDir[2] * fDistance;
}

float GetDifferenceBetweenAngles(float fA[3], float fB[3])
{
    float fFwdA[3]; 
    GetAngleVectors(fA, fFwdA, NULL_VECTOR, NULL_VECTOR);

    float fFwdB[3]; 
    GetAngleVectors(fB, fFwdB, NULL_VECTOR, NULL_VECTOR);

    return RadToDeg(ArcCosine(fFwdA[0] * fFwdB[0] + fFwdA[1] * fFwdB[1] + fFwdA[2] * fFwdB[2]));
}


Medical GetActiveMedical(int client)
{
	int curWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (curWeapon == -1)
		return Medical_None;

	char classname[64];
	GetEntityClassname(curWeapon, classname, sizeof(classname));

	Medical medical = GetMedicalDefinition(curWeapon);
	if (medical != Medical_None)
	{
		MedicalSequence sequence = view_as<MedicalSequence>(GetEntProp(curWeapon, Prop_Send, "m_nSequence"));
		if (sequence == MedicalSequence_Idle || sequence == MedicalSequence_WalkIdle || sequence == MedicalSequence_Run)
			return medical;
	}

	return Medical_None; 
}

bool CanPlayerUseMedical(int client, Medical medical)
{
	// TODO: Clientprefs to toggle freezing on heal
	return TestPreCondForMedical(client, medical);
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
		return;

	lastVoiceTime[client] = curTime;
	float origin[3];
	GetClientAbsOrigin(client, origin);

	TE_Start("TEVoiceCommand");
	TE_WriteNum("_playerIndex", client);
	TE_WriteNum("_voiceCommand", view_as<int>(voice));
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

bool TestPreCondForMedical(int& target, Medical& medical)
{
	switch (medical)
	{
		case Medical_Bandages:
		{
			return IsPlayerBleeding(target);
		}

		case Medical_FirstAidKit:
		{
			return IsPlayerHurt(target);
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


Medical GetMedicalDefinition(int item)
{
	char classname[32];
	GetEntityClassname(item, classname, sizeof(classname));

	if (!strcmp(classname, "item_first_aid"))
		return Medical_FirstAidKit;
	
	if (!strcmp(classname, "item_bandages"))
		return Medical_Bandages;
	
	return Medical_None;
}


float GetMedicalDuration(Medical& medical)
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
