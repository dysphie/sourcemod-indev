

public void OnPluginStart()
{
	RegConsoleCmd("sm_nmo", OnCmdNmo);
}

public Action OnCmdNmo(int client, int args)
{
	char buffer[PLATFORM_MAX_PATH];
	GetCurrentMap(buffer, sizeof(buffer));
	Format(buffer, sizeof(buffer), "maps/%s.nmo", buffer);

	if (!FileExists(buffer, true, NULL_STRING))
	{
		PrintToServer("No NMO exists for map");
		return Plugin_Handled;
	}

	File file = OpenFile(buffer, "rb", true, NULL_STRING);
	if (!file)
	{
		PrintToServer("NMO file could not be opened");
		return Plugin_Handled;
	}

	int version;
	file.ReadInt8(version);

	if (version != 'v') 
	{
		PrintToServer("Unsupported NMO format");
		return Plugin_Handled;		
	}

	ParseObjectivesV1(file);
	delete file;
	return Plugin_Handled;
}

void ParseObjectivesV1(File file)
{
	int padding;
	file.ReadInt32(padding);

	int objectivesCount;
	file.ReadInt32(objectivesCount);

	int antiObjectivesCount;
	file.ReadInt32(antiObjectivesCount);

	int extractionZonesCount;
	file.ReadInt32(extractionZonesCount);

	PrintToServer("------- OBJECTIVES BEGIN -------");
	for (int o; o < objectivesCount; o++)
	{
		int entityId;
		file.ReadInt32(entityId);
		PrintToServer("%d", entityId);

		char objName[256];
		file.ReadString(objName, sizeof(objName), -1);
		PrintToServer(objName);

		char objDesc[256];
		file.ReadString(objDesc, sizeof(objDesc), -1);
		PrintToServer("\t %s", objDesc);

		char boundaryName[256];
		file.ReadString(boundaryName, sizeof(boundaryName), -1);
		PrintToServer("\t %s", boundaryName);

		int itemCount;
		file.ReadInt32(itemCount);
		PrintToServer("\t itemCount: %d", itemCount);

		if (itemCount > 0)
		{
			char[][] itemNames = new char[itemCount][256];
			for (int i; i < itemCount; i++)
			{
				file.ReadString(itemNames[i], 256, -1);
				PrintToServer("\t\t %s", itemNames[i]);
			}			
		}

		int linksCount;
		file.ReadInt32(linksCount);
		PrintToServer("\tlinksCount: %d", linksCount);

		if (linksCount > 0)
		{
			int[] objLinks = new int[linksCount];
			for (int j; j < linksCount; j++)
			{
				file.ReadInt32(objLinks[j]);
				PrintToServer("\t\t %d", objLinks[j]);
			}	
		}
	}
	PrintToServer("------- OBJECTIVES END -------");

	PrintToServer("------- ANTI-OBJECTIVES BEGIN -------");
	for (int a; a < antiObjectivesCount; a++)
	{
		int entityId;
		file.ReadInt32(entityId);

		char antiName[256];
		file.ReadString(antiName, sizeof(antiName), -1);
		PrintToServer(antiName);

		int itemCount;
		file.ReadInt32(itemCount);
		PrintToServer("\t itemCount: %d", itemCount);

		if (itemCount > 0)
		{
			char[][] itemNames = new char[itemCount][256];
			for (int i; i < itemCount; i++)
			{
				file.ReadString(itemNames[i], 256, -1);
				PrintToServer("\t\t %s", itemNames[i]);
			}			
		}
	}

	PrintToServer("------- ANTI-OBJECTIVES END -------");
	PrintToServer("------- EXTRACTION ZONES BEGIN -------");

	for (int e; e < extractionZonesCount; e++)
	{
		int entityId;
		file.ReadInt32(entityId);

		char zoneName[256];
		file.ReadString(zoneName, sizeof(zoneName), -1);
		PrintToServer(zoneName);
	}

	PrintToServer("------- EXTRACTION ZONES END -------");
}

