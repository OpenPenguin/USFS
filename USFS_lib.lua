--[[
    USFS - Ultra-Simple File System
    Developed by Ethan Manzi (coderboy14)

    General:
        The data block will always grow UP from the TAIL of the disk, and the super-block will always be the first thing at the
        start! If the data block's name doesn't use the entire provided space, IT MUST BE PADDED!

    Super-Block Structure: (42 bytes)
        - 00: 2 bytes, block size
        - 02: 4 bytes, size of data in blocks
        - 06: 4 bytes, blocks used
        - 10: 4 bytes, index table length
        - 14: 4 bytes, file count
        - 18: 4 bytes, size of reserved area
        - 22: 2 bytes, patch number
        - 24: 3 bytes, magic number
        - 27: 1 bytes, version in BCD
        - ??: 4 bytes, first table index
        - ??: 4 bytes, last block
        - ??: 4 bytes, last folder
        - ??: 2 bytes, max file name length (in bytes)

    Data Block Structure: (minimum 56 bytes)
        - 1 bytes, type
        - 1 bytes, state
        - 4 bytes, block ID
        - 4 bytes, file ID
        - 4 bytes, previous segment
        - 4 bytes, next segment
        - 4 bytes, parent ID
        - 2 bytes, permissions
        - 4 bytes, pointer (the chunk # of the actual data)
        - 4 bytes, length
        - 4 bytes, previous sibling
        - 4 bytes, next sibling,
        - 4 bytes, next folder
        - 4 bytes, first child
        - 4 bytes, last child
        - 4 bytes, child count
        - ? bytes, name     (the maximum length of the name will be specified in the superblock)
]]

local USFS = {}
    -- Constants
    local _CONST = {
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

return USFS