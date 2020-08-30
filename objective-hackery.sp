#include <sdktools>

public Plugin myinfo = {
    name        = "[NMRiH] Objective Skipping",
    author      = "Dysphie",
    description = "Handle objective skips gracefully",
    version     = "0.1.0",
    url         = ""
};

#define ASSERT(%1) if (!%1) ThrowError("#%1")

stock Address operator+(Address base, int off) {
	return base + Address:off;
}

methodmap AddressBase {
	property Address addr {
		public get() { 
			return Address:this; 
		}
	}
}

methodmap UtlVector < AddressBase 
{
	public UtlVector(Address addr) {
		return UtlVector:addr;
	}

	property int size {
		public get() {
			return LoadFromAddress(this.addr + 0xC, NumberType_Int32);
		}
	}

	property Address elements {
		public get() {
			return Address:LoadFromAddress(this.addr, NumberType_Int32);
		}
	}

	public any Get(int idx, int elemSize = 0x4) {
		return any:LoadFromAddress(this.elements + idx * elemSize, NumberType_Int32);
	}

	public int FindValue(int value)
	{
		int max = this.size;
		for (int i; i < max; i++)
			if (this.Get(i) == value)
				return value;
		return -1;
	}
}

methodmap ObjectiveBoundary < AddressBase {

	public ObjectiveBoundary(Address addr) {
		return ObjectiveBoundary:addr;
	}

	public void Finish() {
		ObjectiveBoundary_Finish(this.addr);
	}
}

methodmap Objective < AddressBase {

	public Objective(Address addr) {
		return Objective:addr;
	}

	property int id {
		public get() { 
			return LoadFromAddress(this.addr, NumberType_Int32);
		}
	}

	property int name {
		public get() {
			return LoadFromAddress(this.addr + 0x4, NumberType_Int32);
		}
	}

	property int description {
		public get() {
			return LoadFromAddress(this.addr + 0x8, NumberType_Int32);
		}
	}

	property Address entityList {
		public get() {
			return this.addr + 0xC;
		}
	}

	property Address links {
		public get() {
			return this.addr + 0x20;
		}
	}

	property bool anti {
		public get() {
			return !!LoadFromAddress(this.addr + 0x34, NumberType_Int8);
		}
	}

	property int boundaryName {
		public get() {
			return LoadFromAddress(this.addr + 0x38, NumberType_Int32);
		}
	}

	public UtlVector GetLinks() {
		return UtlVector(this.links);
	}

	public UtlVector GetEntityList() {
		return UtlVector(this.entityList);
	}

	// TODO: return bytes written
	public void GetName(char[] buffer, int maxlen) {	
		ASSERT(this.name);
		UTIL_StringtToCharArray(Address:this.name, buffer, maxlen);
	}

	// ^
	public void GetDescription(char[] buffer, int maxlen) {
		ASSERT(this.name);
		UTIL_StringtToCharArray(Address:this.description, buffer, maxlen);
	}

	// FIXME: Returns true for non end objectives 
	// TODO: Fetch obj chain vector and findvalue to see if index equals len-1
	public bool IsEndObjective() {
		return false;
	}
}

methodmap ObjectiveManager < AddressBase {

	public ObjectiveManager(Address addr) {
		return ObjectiveManager:addr;
	}

	property ObjectiveBoundary currentObjectiveBoundary {
		public get() {
			Address addr = Address:LoadFromAddress(this.addr + 0x7C, NumberType_Int32);
			return ObjectiveBoundary(addr);
		}
	}

	property int currentObjectiveIndex {
		public get() {
			return LoadFromAddress(this.addr + 0x70, NumberType_Int32);
		}

		public set(int value) {
			StoreToAddress(this.addr + 0x70, value, NumberType_Int32);
		}
	}

	property Objective currentObjective {
		public get() {
			Address addr = Address:LoadFromAddress(this.addr + 0x78, NumberType_Int32);
			return Objective(addr);
		}
	}

	property UtlVector objectiveChain {
		public get() {
			return UtlVector(this.addr + 0x58);
		}
	}

	property UtlVector objectives {
		public get() {
			return UtlVector(this.addr + 0x14);
		}
	}

	property bool completed {
		public get() {
			return !!LoadFromAddress(this.addr + 0x6C, NumberType_Int8);
		}

		public set(bool value) {
			StoreToAddress(this.addr + 0x6C, value, NumberType_Int8);
		}
	}

	public void StartNextObjective() {
		ObjectiveManager_StartNextObjective(this.addr);
	}

	public void CompleteCurrentObjective() {
		ObjectiveBoundary boundary = this.currentObjectiveBoundary;

		if (boundary)
			boundary.Finish();

		// FIXME: IsEndObjective returns true for non end objectives

		// Objective objective = this.currentObjective;
		// ASSERT(objective);

		// if (objective.IsEndObjective())
		// {
		// 	PrintToServer("Is end objective");
		// 	this.completed = true;
		// }
		// else
		// {
			// PrintToServer("Is not end objective");
		this.currentObjectiveIndex++;
		this.StartNextObjective();
		// }
	}

	public int GetObjectiveIndex(Objective objective) {
		UtlVector chain = this.objectiveChain;
		ASSERT(chain);
		
		int len = chain.size;
		for (int i; i < len; i++)
			if (chain.Get(i) == objective.id)
				return i; 
		return -1;
	}

	public Objective GetObjectiveByID(int id) {
		return ObjectiveManager_GetObjectiveById(this.addr, id);
	}

}

ObjectiveManager objMgr;

Handle hBoundaryFinish;
Handle hStartNextObjective;
Handle hGetObjectiveByID;
bool g_bIgnoreObjectives;
UtlVector g_ObjectiveChain;

public void OnMapReset()
{
	g_ObjectiveChain = objMgr.objectiveChain;
}

public void OnMapStart()
{
	g_ObjectiveChain = objMgr.objectiveChain;
}

public void OnPluginStart()
{
	GameData gamedata = new GameData("objectives.nmrih");
	if(!gamedata)
		SetFailState("Failed to load gamedata");

	objMgr = ObjectiveManager(gamedata.GetAddress("CNMRiH_ObjectiveManager"));
	if(!objMgr.addr)
		SetFailState("Failed to retrieve the objective manager");

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetSignature(SDKLibrary_Server, "\x55\x8B\xEC\x56\x8B\x71\x20", 7);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	hGetObjectiveByID = EndPrepSDKCall();
	ASSERT(hGetObjectiveByID);

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetSignature(SDKLibrary_Server, 
		"\x55\x8B\xEC\x51\x56\x57\x8B\xF9\xC6\x45\xFF\x00\x8D\x4D\xFF\x8A\x87\x8C\x03\x00\x00", 21);
	hBoundaryFinish = EndPrepSDKCall();
	ASSERT(hBoundaryFinish);

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetSignature(SDKLibrary_Server, 
		"\x55\x8B\xEC\x83\xEC\x2C\x53\x56\x57\x8B\xF9\x89\x7D\xF8", 14);
	hStartNextObjective = EndPrepSDKCall();
	ASSERT(hStartNextObjective);

	HookEvent("objective_complete", OnObjectiveComplete, EventHookMode_Pre);
	HookUserMessage(GetUserMessageId("ObjectiveNotify"), OnObjectiveNotify, true);
	RegAdminCmd("sm_test", OnCmdTest, ADMFLAG_GENERIC, "Tests various calls");
	RegAdminCmd("sm_chain", OnCmdChain, ADMFLAG_GENERIC, "Prints objective chain");
}


public Action OnCmdChain(int client, int args)
{
	int max = g_ObjectiveChain.size;
	for (int i; i < max; i++)
		PrintToServer("%d", g_ObjectiveChain.Get(i));

	return Plugin_Handled;
}

public Action OnCmdTest(int client, int args)
{
	UtlVector objectives = objMgr.objectives;

	char sObjName[255];
	char sObjDesc[255];

	int maxObjs = objectives.size;
	for(int i; i < maxObjs; i++)
	{
		char sObjLinks[255];
		char sObjEnts[1024];

		Objective obj = objectives.Get(i);

		int objID = obj.id;

		obj.GetName(sObjName, sizeof(sObjName));
		obj.GetDescription(sObjDesc, sizeof(sObjDesc));

		int index = g_ObjectiveChain.FindValue(objID);

		UtlVector links = obj.GetLinks();
		int maxLinks = links.size;
		for(int j; j < maxLinks; j++)
		{
			Objective linkedObj = objMgr.GetObjectiveByID(links.Get(j));
			if (!linkedObj)
				continue;

			char sLinkedObjName[64];
			linkedObj.GetName(sLinkedObjName, sizeof(sLinkedObjName));
			Format(sObjLinks, sizeof(sObjLinks), "%s%s ", sObjLinks, sLinkedObjName);
		}
		
		UtlVector entities = obj.GetEntityList();
		int maxEnts = entities.size;
		for(int j; j < maxEnts; j++)
		{
			char buffer[32];
			UTIL_StringtToCharArray(entities.Get(j), buffer, sizeof(buffer));

			Format(sObjEnts, sizeof(sObjEnts), "%s%s ", sObjEnts, buffer);
		}

		PrintToServer("[%d] %d: %s - %s [end: %d] \n Links-> %s \n Ents-> %s", 
			index, objID, sObjName, sObjDesc, obj.IsEndObjective(), sObjLinks, sObjEnts);
	}

	return Plugin_Handled;
}


public Action OnObjectiveNotify(UserMsg msg, BfRead bf, const int[] players, int playersNum, 
	bool reliable, bool init)
{
	return g_bIgnoreObjectives ? Plugin_Handled : Plugin_Continue; 
}

public void ObjectiveManager_StartNextObjective(Address addr)
{ 
	SDKCall(hStartNextObjective, addr);
}

public void ObjectiveBoundary_Finish(Address addr)
{
	SDKCall(hBoundaryFinish, addr);
}

Objective ObjectiveManager_GetObjectiveById(Address self, int id)
{
	return Objective((SDKCall(hGetObjectiveByID, self, id)));	
}

void UTIL_StringtToCharArray(Address pSrc, char[] dest, int len)
{
	int i;
	while (--len && (dest[i] = LoadFromAddress(pSrc + Address:i, NumberType_Int8)) != 0)
		i++; 
	dest[i] = 0;
}

public Action OnObjectiveComplete(Event event, const char[] name, bool silent)
{
	if (g_bIgnoreObjectives)
		return Plugin_Continue;

	Objective pCurObj = objMgr.currentObjective;
	ASSERT(pCurObj);

	int doneObjIdx = g_ObjectiveChain.FindValue(event.GetInt("id"));
	int curObjIdx = g_ObjectiveChain.FindValue(pCurObj.id);

	int numSkipped = doneObjIdx - curObjIdx;

	if (numSkipped > 0)
	{
		g_bIgnoreObjectives = true;
		do {
			objMgr.CompleteCurrentObjective();
			numSkipped--;
		} while (numSkipped)
		g_bIgnoreObjectives = false;
	}

	PrintToServer("done idx = %d, cur idx = %d", doneObjIdx, curObjIdx);

	return Plugin_Continue;
}

public Action OnCmdNext(int client, int args)
{
	objMgr.CompleteCurrentObjective();
	return Plugin_Handled;
}