

local parser = {};


-- What a wonderful thing, structure!
-- The keys in this table are the names of each command.
-- The values are structures as such, containing functions which are passed the arguments and identification/user:
-- {
--  validate -> bool, string; whether the arguments are correct, and if not, why. Called with the current user as well;
--  hexside -> bool; whether it needs to be sent to the hex side;
--  handler -> bool; called with a "send data to hex" function which takes in a string, only if hexside is true, alongside an error callback. Handles all logic required, returns whether it was a success;
--  handlerid -> string; which handler hex to use for this command, if hexside is true;
--  hexargs -> {string}; which arguments are required for the handler hex, if hexside is true;
--  baseargs -> {int}; which <i>static</i> argument ids to pass into the handler hex, if hexside is true;
-- }. These are checked sequentially.
local commands = {};
local HexArgs = {};
local HexArgCollectors = {};
local BaseArgRegistration = {};

-- handler id to packager peripheral mapping
local handlerID_to_packager = {};

-- can send up to 1728 chars worth of data. Do not exceed this, please.
local function sendDataToHex(data, handlerid)
    local packager_to_use = handlerID_to_packager[handlerid];

    packager_to_use.setAddress(table.concat(data, "\
") .. (os.epoch("local")/1000));
end

function parser.registerCommand(commandName, validate, hexside, handler, handlerid, hexargs, baseargs)
    commands[commandName] = {
        ["validate"] = validate,
        ["hexside"] = hexside,
        ["handler"] = handler,
        ["handlerid"] = handlerid,
        ["hexargs"] = hexargs,
        ["baseargs"] = baseargs
    }
end

function parser.registerHandler(id, packager)
    handlerID_to_packager[id] = packager;
end

function parser.registerHexArgs(hexargName, hexargCollector, hexargID)
    assert(hexargName and hexargCollector and hexargID, "Registered with nil parameters.");
    HexArgs[hexargName] = hexargID;
    HexArgCollectors[hexargID] = hexargCollector;
end

--- Takes in the command, the arguments to the command, and a callback should there be any errors. Executes the command.
--- The error callback will be called with a string describing what happened if there is an error.
function parser.command(command, args, identification, error_callback)
    local commandData = commands[command];
    if ((not commandData) or (not commandData["validate"])) then
        error_callback("Command does not exist. If this does exist, contact an administrator.");
        return;
    end
    local validated, whyWrong = (commandData["validate"])(args, identification);
    if (not validated) then
        error_callback("Incorrect arguments: " .. whyWrong);
        return;
    end
    local hexside = ((commandData["hexside"]))(args, identification);
    local data_to_send = {};
    local handlerdata = {};
    local stop_send = false;
    if not ((commandData["handler"])(args, identification, function(toSend)
        if type(toSend) ~= "string" then
            error_callback(string.format("Internal error: non-string data passed into hex. Type is %s. Contact an administrator.", type(toSend)));
            stop_send = true;
            return;
        end
        table.insert(handlerdata, toSend);
    end, error_callback)) then
        return;
    end;
    if stop_send then
        error_callback("Internal error! aborting!");
        return;
    end
    table.insert(data_to_send, table.concat(handlerdata, "˚"));
    print("Inserted handler data!");

    if (hexside) then
        print("Hexside!");
        local handlerID = (commandData["handlerid"])(args, identification);

        if (not handlerID_to_packager[handlerID]) then
            error_callback(string.format("Internal error: handler %s does not exist/is not registered. Contact an administrator.", handlerID));
            return;
        end

        local hexargs = (commandData["hexargs"])(args, identification);
        local truehexargs = {};
        for i,v in pairs(hexargs) do
            local truehexarg = HexArgs[v];
            if (not truehexarg) then
                error_callback(string.format("Internal error. Hexarg %s is invalid. Contact an administrator.", v));
                return;
            end
            table.insert(truehexargs, truehexarg);
            table.insert(truehexargs, (HexArgCollectors[truehexarg])(args, identification))
        end
        local hexargsstring = table.concat(truehexargs, "˚")
        local baseargs = (commandData["baseargs"])(args, identification);
        for i, v in pairs(baseargs) do
            if (not BaseArgRegistration[v]) then
                error_callback(string.format("Internal error. Basearg %d is invalid. Contact an administrator.", v));
                return;
            end
        end
        local baseargstring = table.concat(baseargs, "˚");

        table.insert(data_to_send, hexargsstring);
        table.insert(data_to_send, baseargstring);
        table.insert(data_to_send, handlerID);
        print(textutils.serialise(data_to_send));
        sendDataToHex(data_to_send, handlerID);
    end
end

return parser