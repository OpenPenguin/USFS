--[[
    USFS - Ultra-Simple File System
    Developed by Ethan Manzi (coderboy14)
]]

local USFS = {}
    -- Constants
    local _CONST = {
        ["defaults"] = {
            ["chunkSize"] = 512
        },
        ["magicBytes"] = {0x75, 0x73, 0x34},
        ["superBlock"] = {
            ["size"] = 42,
            ["structure"] = {
                {["offset"]=0,  ["size"]=2, ["name"]="blockSize"},
                {["offset"]=2,  ["size"]=4, ["name"]="dataBlockCount"},
                {["offset"]=6,  ["size"]=4, ["name"]="blocksUsed"},
                {["offset"]=10, ["size"]=4, ["name"]="indexTableLength"},
                {["offset"]=14, ["size"]=4, ["name"]="fileCount"},
                {["offset"]=18, ["size"]=4, ["name"]="reservedAreaLength"},
                {["offset"]=22, ["size"]=2, ["name"]="patchNumber"},
                {["offset"]=24, ["size"]=3, ["name"]="magicNumber"},
                {["offset"]=27, ["size"]=1, ["name"]="version"},
                {["offset"]=28, ["size"]=4, ["name"]="firstTableIndex"},
                {["offset"]=32, ["size"]=4, ["name"]="lastBlock"},
                {["offset"]=36, ["size"]=4, ["name"]="lastFolder"},
                {["offset"]=40, ["size"]=2, ["name"]="maxFileNameLength"}
            }
        },
        ["dataBlockEntry"] = {
            ["minSize"] = 56,
            ["structure"] = {
                {["offset"]=0,  ["size"]=1, ["name"]="type"},
                {["offset"]=1,  ["size"]=1, ["name"]="state"},
                {["offset"]=2,  ["size"]=4, ["name"]="blockID"},
                {["offset"]=6,  ["size"]=4, ["name"]="objectID"},
                {["offset"]=10, ["size"]=4, ["name"]="previousSegment"},
                {["offset"]=14, ["size"]=4, ["name"]="nextSegment"},
                {["offset"]=18, ["size"]=4, ["name"]="parentID"},
                {["offset"]=22, ["size"]=2, ["name"]="permissions"},
                {["offset"]=24, ["size"]=4, ["name"]="pointer"},
                {["offset"]=28, ["size"]=4, ["name"]="length"},
                {["offset"]=32, ["size"]=4, ["name"]="previousSibling"},
                {["offset"]=36, ["size"]=4, ["name"]="nextSibling"},
                {["offset"]=40, ["size"]=4, ["name"]="nextFolder"},
                {["offset"]=44, ["size"]=4, ["name"]="firstChild"},
                {["offset"]=48, ["size"]=4, ["name"]="lastChild"},
                {["offset"]=52, ["size"]=4, ["name"]="childCount"},
                {["offset"]=56, ["size"]=0, ["name"]="name"}
            }
        }
    }

    --  Helpers
    function readBytes(proxy, initalOffset, size)
        local data = {}
        for offset=0, size do
            data[offset] = proxy.readByte(initalOffset + offset)
        end
        return data
    end

    function unsign(value)
        return value + 128
    end
    function sign(value)
        return value - 128
    end

    function newFourByteNumber(byte1, byte2, byte3, byte4)
        local fbn = {}

        --  This will REALLY need improving later, so I can actually do math with these four bit numbers
        --  For now, all I need is an incrementation method, and a way to access the bytes

        function fbn:increment(by)
            local bytes = rawget(self, "bytes")
            if by == nil then
                by = 1
            end
            for i=4, 2, -1 do
                if bytes[i] > 255 then
                    bytes[i] = 0
                    bytes[i - 1] = bytes[i - 1] + 1
                end
                bytes[i] = bytes[i] + 1
                if bytes[i] > 255 then
                    bytes[i] = 0
                    bytes[i - 1] = bytes[i - 1] + 1
                end
            end
            if bytes[1] > 255 then
                bytes = {0,0,0,0}
            end
            rawset(self, "bytes", bytes)
        end

        function fbn:getBytes()
            return rawget(self, "bytes")
        end

        return setmetatable({["bytes"]={byte1,byte2,byte3,byte4}}, fbn)
    end

    --  Static Methods
    function USFS.formatDisk(diskProxy)

    end

    function USFS.new(diskProxy)
        local USFSObject = setmetatable({["proxy"] = diskProxy, ["cache"]={}, ["superblock"]=nil}, USFS)
        return USFSObject
    end

    function USFS.getMagicNumber()
        return _CONST["magicBytes"]
    end

    function USFS.getDisksSuperBlock(diskProxy)
        local data = {}
        for structureRow, row in pairs(_CONST["superBlock"]["structure"]) do
            data[row["name"]] = readBytes(diskProxy, row["offset"], row["size"])
        end
        return data
    end

    --  Object Methods
    function USFS:init()
        self:readSuperBlock()
    end

    function USFS:clearCache()
        rawset(self, "cache", {})
    end

    function USFS:readSuperBlock()
        rawset(
            self, 
            "superblock", 
            assert(
                USFS.getDisksSuperBlock(assert(rawget(self, "proxy"), "Unable to get disk proxy!")), 
                "Unable to read super disk!"
            )
        )
    end

    function USFS:incrementSuperBlockTableLength(count)
        local proxy = rawget(self, "proxy")
        if count == nil then
            count = 1
        end
        local superblock = rawget(self, "superblock")
        local tableLengthIndex = _CONST["superBlock"]["structure"][4]
        local offset = tableLengthIndex["offset"]
        
        local currentValue = superblock["indexTableLength"]
        local convobj = newFourByteNumber(
            unsign(currentValue[1]), 
            unsign(currentValue[2]), 
            unsign(currentValue[3]), 
            unsign(currentValue[4])
        )
        convobj:increment(1)
        local newValue = convobj:getBytes()

        proxy.writeByte(offset + 0, sign(newValue[1]))
        proxy.writeByte(offset + 1, sign(newValue[2]))
        proxy.writeByte(offset + 2, sign(newValue[3]))
        proxy.writeByte(offset + 3, sign(newValue[4]))

        superblock["indexTableLength"] = {sign(newValue[1]), sign(newValue[2]), sign(newValue[3]), sign(newValue[4])}
        rawset(self, "superblock", superblock)
    end

    function USFS:writeSuperBlock(newSuperBlock)
        --  Write out a new super block!
        if newSuperBlock == nil then
            newSuperBlock = rawget(self, "superblock")
        end
    end

    function USFS:ensureMinimumCache()
        local cache = rawget(self, "cache")
        if (
            (cache["dataBlockEntryLength"] == nil)
        ) then
            self:buildMinimumCache()
        end
    end

    function USFS:buildMinimumCache()
        local cache = rawget(self, "cache")
        local superblock = rawget(self, "superblock")
        local dblockInfo = _CONST["dataBlockEntry"]
        cache["dataBlockEntryLength"] = dblockInfo["minSize"] + superBlock["maxFileNameLength"]
        rawset(self, "cache", cache)
    end

    function USFS:readIndexTableEntry(ID)
        self:ensureMinimumCache()
        local cache = rawget(self, "cache")
        local superblock = rawget(self, "superblock")
        local dblockInfo = _CONST["dataBlockEntry"]

        -- The pointer is to the BOTTOM of the entry. I need the TOP. Pointers START at 1
        local pointer = superBlock["firstTableIndex"] - (cache["dataBlockEntryLength"] * ID)

        local data = {}
        for rowID, row in pairs(_CONST["dataBlockEntry"]["structure"]) do
            if row["name"] == "name" then
                data["name"] = readByte(proxy, pointer + row["offset"], superBlock["maxFileNameLength"])
            else
                data[row["name"]] = readBytes(proxy, pointer + row["offset"], row["size"])
            end
        end
        return data
    end

    function USFS:buildDirectoryTree()
        local proxy = rawget(self, "proxy")
        local cache = rawget(self, "cache")

        --  Step one, get ALL the folders. The objectID for the trunk (which will ALWAYS be the first item) is 1. Zero is NULL.
        local folders = {}

        local target = 1
        while (target ~= 0) do
            local result = self:readIndexTableEntry(target)
            target = result["nextFolder"]
            table.insert(folders, result)
        end

        --  Now we have all the folders, they're just not in order! The next step is to create a flat index map.
        --  Meaning the data won't be in a hiearchy just yet, it'll just essentially list everyone's children

        local map = {}

        for folderID, folder in pairs(folders) do
            map[folder["objectID"]] = {["id"] = folder["objectID"], ["object"] = folder, ["children"] = {}}
        end

        --  Now go through and continously reduce the map until there's only the trunk left
        local function recursivlySearchForParents(searchTarget, parentID)
            for objectID, object in pairs(searchTarget) do
                if objectID == target["object"]["parentID"] then
                    return map[objectID]
                else
                    local rcr = recursivlySearchForParents(object["children"], parentID)
                    if rcr == true then
                        return rcr
                    end
                end
            end
            return nil
        end

        local function searchForParent(target)
            local parent = nil
            parent = recursivlySearchForParents(map, target)
            if not parent == nil then
                table.insert(parent["children"], object)
                return
            end
            error("Parent not found!")
        end

        while (#map > 1) do
            local target = table.remove(map)
            searchForParent(target)
        end

        --  There we go! We now have a tree!
        cache["structureTree"] = map
        rawset(self, "cache", cache)

        return map
    end

    function USFS:allocateIndexEntry()
        --  Just a combo caller. It first checks if it can reallocate an index entry, and if not, it creates one
    end

    function USFS:createIndexEntry()
        --  Create a brand new entry at the very end of the table. This should be done AFTER you try running the reallocateIndexEntry
        --  method! Otherwise, a bunch of unused space will exist!
        local superblock = rawget(self, "superblock")
    end

    function USFS:reallocateIndexEntry()
        --  Search through the index table, to find the first free place to add a new entry
        --  Recall, if the entry has a type zero, that means unused (NULL), meaning we can overwrite that slot!
        local superblock = rawget(self, "superblock")
        for entryID=1, superblock["indexTableLength"] do
            local entry = self:readIndexTableEntry(entryID)
            if entry["type"] == 0 then
                return entryID
            end
        end
        return nil
    end

    function USFS:buildChunkMap()
        -- Build a map of all the chunks, and their availablity status
        local chunks = {["all"] = {}, ["free"] = {}, ["used"] = {}, ["trash"] = {}}
        local proxy = rawget(self, "proxy")
        local cache = rawget(self, "cache")

        local totalEntries = 
    end

    function USFS:buildTrashList()
        --  Create a list of all objects that are TRASHED, but not 
    end

return USFS