unit syncutils;
{
    A Unit to support the tomboy-ng sync unit
    Copyright (C) 2018 David Bannon
    See attached licence file.

    HISTORY
    2018/10/25  Much testing, support for Tomdroid.
    2018/10/28  Added SafeGetUTCC....
    2018/06/05  Func. to support Tomboy's sync dir names, rev 431 is in ~/4/341
    2019/06/07  Don't check for old sync dir model, for 0 its the same !
    2019/07/19  Added ability to escape ' and " selectivly, attributes ONLY
    2020/04/24  Make debugln use dependent on LCL, now can be FPC only unit
    2020/08/01  Can now handle 'Zulu' datestrs, ones without timezone, with 'Z'
}
{$mode objfpc}{$H+}

interface

uses
    Classes, SysUtils, dateutils, LazLogger;

type TSyncTransport=(SyncFile,  // Sync to locally available dir, things like smb: mount, google drive etc
		        SyncNextCloud,  // Sync to NextCloud using Nextcloud Notes
                SyncAndroid);  // Simple one to one Android Device

type TSyncAction=(SyUnset,      // initial state, should not be like this at end.
                SyNothing,      // This note, previously sync'ed has not changed.
                SyUploadNew,    // This a new local note, upload it.
                SyUploadEdit,   // A previously synced note, edited locally, upload.
                SyDownload,     // A new or edited note from elsewhere, download.
                SyDeleteLocal,  // Synced previously but no longer present on server, delete locally
                SyDeleteRemote, // Marked as having been deleted locally, so remove from server.
                SyClash,        // Edited both locally and remotly, policy or user must decide.
                SyError,
                SyAllRemote,    // Clash Decision - Use remote note for all subsquent clashes
                SyAllLocal,     // Clash Decision - Use local note for all subsquent clashes
                SyAllNewest,    // Clash Decision - Use newest note for all subsquent clashes
                SyAllOldest);   // Clash Decision - Use oldest note for all subsquent clashes

        // Indicates the readyness of a sync connection
type TSyncAvailable=(SyncNotYet,        // Initial state.
                    SyncReady,          // We are ready to sync, looks good to go.
                    SyncNoLocal,        // We don't have a local manifest, only an error if config thinks there should be one.
                    SyncNoRemoteMan,    // No remote manifest, an uninitialized repo perhaps ?
                    SyncNoRemoteRepo,   // Filesystem is OK but does not look like a repo.
                    SyncBadRemote,      // Has either Manifest or '0' dir but not both.
                    SyncNoRemoteDir,    // Perhaps sync device is not mounted, Tomdroid not installed ?
                    SyncNoRemoteWrite,  // no write permission, do not proceed!
                    SyncMismatch,       // Its a repo, Captain, but not as we know it.
                    SyncXMLError,       // Housten, we have an XML error in a manifest !
                    SyncBadError,       // Some other error, must NOT proceed.
                    SyncNetworkError,   // Remove server/device not responding
                    SyncCredentialError); // Unsuitable user:password

type TRepoAction = (
                RepoJoin,               // Join (and use) an existing Repo
                RepoNew,                // Create (and use) a new repo in presumably a blank dir
                RepoUse,                // Go ahead and use this repo to sync
                RepoForce,              // Force join or create, even if existing credentuals don't work
                RepoTest);              // Just have a look, maybe call SetTransport ?

type
  	PNoteInfo=^TNoteInfo;
  	TNoteInfo = record
        ID : ANSIString;            // The 36 char ID
        LastChangeGMT : TDateTime;  // Compare less or greater than but not Equal !
        CreateDate : ANSIString;
        LastChange : ANSIString;    // leave as strings, need to compare and TDateTime uses real
        Rev : Integer;              // Not used for uploads, Trans knows how to inc its own.
        Deleted: Boolean;
        SID : longint;              // Short ID, clumbsy alt to the GUID/UUID we should use
        Action : TSyncAction;
        Title : ANSIString;
    end;

 type                                 { ---------- TNoteInfoList ---------}

   { TNoteInfoList }

   TNoteInfoList = class(TList)
    private


     	function Get(Index: integer): PNoteInfo;
    public
        ServerID : string;              // Partially implemented, don't rely yet ....
        LastSyncDateSt : string;        // Partially implemented, don't rely yet ....
        LastSyncDate : TDateTime;       // Partially implemented, don't rely yet ....
        LastRev : integer;              // Partially implemented, don't rely yet ....
        destructor Destroy; override;
        function Add(ANote : PNoteInfo) : integer;
        function FindID(const ID : ANSIString) : PNoteInfo;
                                        // returns the ID, a GUID, for a given short id
        function FindID(sid : longint): string;
        function FindSID(const SID: longint): PNoteInfo;
        function ActionName(Act : TSyncAction) : string;
        function AddByFileName(FFilename: string; Act: TSyncAction; Rev: integer=0): boolean;
        property Items[Index: integer]: PNoteInfo read Get; default;
    end;

                                    { ------------- TClashRecord ------------- }
        { A couple of types used to manage the data involved in handling
          a sync clash.
        }
 type
    TClashRecord = record
        Title : ANSIString;
        NoteID : ANSIString;
        //ServerLastChange : ANSIString;
        //LocalLastChange : ANSIString;
        ServerFileName : string;
        LocalFileName : string;
    end;


 type    TProceedFunction = function(const ClashRec : TClashRecord): TSyncAction of object;


    { takes a path to the server and a rev number and returns a Tomboy style sync dir.
      or, if NoteID (without '.note') is supplied, a FullNoteName   }
function GetRevisionDirPath (ServerPath : string; Rev : integer; NoteID : string = '') : string;

    { Returns True if this Sync Dir is in correct (ie Tomboy or tomboy-ng later
      than may 2019 mode) place.
      eg revision 431 should be in $SYNCDIR/4/431 but might be in 0/431 }
function UsingRightRevisionPath(ServerPath : string; Rev : integer) : boolean;

   // Takes a normal Tomboy DateTime string and converts it to UTC, ie zero offset
function ConvertDateStrAbsolute(const DateStr : string) : string;

                // A safe, error checking method to convert Tomboy's ISO8601 33 char date string to TDateTime
function SafeGetUTCfromStr(const DateStr : string; out DateTime : TDateTime; out ErrorMsg : string) : boolean;

                // Ret GMT from tomboy date string, 0.0 on error or unlikely date.
function GetGMTFromStr(const DateStr: ANSIString): TDateTime;

                // Ret a tomboy date string for now.
//function GetLocalTime: ANSIstring;

        // Returns the LCD string, '' and setting Error to other than '' if something wrong
function GetNoteLastChangeSt(const FullFileName : string; out Error : string) : string;

        // returns false if GUID does not look OK
function IDLooksOK(const ID : string) : boolean;

        // Use whenever we are writing content that may contain <>& to XML files
        // If DoQuotes is true, we also convert ' and " (for xml attributes).
function RemoveBadXMLCharacters(const InStr : ANSIString; DoQuotes : boolean = false) : ANSIString;

                        { ret true if it really has removed the indicated file. Has proved
                          necessary to do this on two end user's windows boxes. Writes debuglns
                          if it has initial problems, returns F and sets ErrorMsg if fails.}
function SafeWindowsDelete(const FullFileName : string; var ErrorMsg : string) : boolean;

                        { returns a version of passed string with anything between < > }
function RemoveXml(const St : AnsiString) : AnsiString;

                        { returns a GUID/UUID suitable for tomboy use }
function MakeGUID() : string;


RESOURCESTRING
  rsNewUploads = 'New Uploads    ';
  rsEditUploads = 'Edit Uploads   ';
  rsDownloads = 'Downloads      ';
  rsLocalDeletes = 'Local Deletes  ';
  rsRemoteDeletes = 'Remote Deletes ';
  rsClashes = 'Clashes        ';
  rsDoNothing = 'Do Nothing     ';
  rsSyncERRORS = 'ERRORS (see consol log) ';

  rsNoNotesNeededSync = 'No notes needed syncing. You need to write more.';
  rsNotesWereDealt = ' notes were dealt with.';
  rsChangeExistingSync = 'Change existing sync connection ?';
  rsNotRecommend = 'Generally not recommended.';
  rsNextBitSlow = 'Next bit can be a bit slow, please wait';

            { -------------- implementation ---------------}
implementation

uses laz2_DOM, laz2_XMLRead, LazFileUtils;

function RemoveXml(const St : AnsiString) : AnsiString;
var
    X, Y : integer;
    FoundOne : boolean = false;
begin
    Result := St;
    repeat
        FoundOne := False;
        X := Pos('<', Result);      // don't use UTF8Pos for byte operations
        if X > 0 then begin
            Y := Pos('>', Result);
            if Y > 0 then begin
                Delete(Result, X, Y-X+1);
                FoundOne := True;
            end;
        end;
    until not FoundOne;
    Result := trim(Result);
end;

function SafeWindowsDelete(const FullFileName : string; var ErrorMsg : string) : boolean;
begin
    // This whole block is here because of issue #132 where windows seemed to have problems
    // moving, deleting a note before a new version is copied over. Is the problem
    // that windows deletefileUTF8() is not settings its return value correctly ??
    if not DeleteFile(FullFileName) then begin
    	ErrorMsg := SysErrorMessage(GetLastOSError);
        {$ifdef LCL}Debugln{$else}writeln{$endif}('Failed using DeleteFileUTF8 - file name is :' + FullFilename);
    	{$ifdef LCL}Debugln{$else}writeln{$endif}('OS Error Msg : ' + ErrorMsg);

    	if not FileExistsUTF8(FullFileName) then
            debugln('But, FileExists says its gone, proceed !')
        else begin
    		{$ifdef LCL}Debugln{$else}writeln{$endif}('I can confirm its still there .');
    	    {$ifdef LCL}Debugln{$else}writeln{$endif}('Trying a little sleep...');
    	    sleep(10);
    	    if not DeleteFileUTF8(FullFileName) then begin
                if not FileExistsUTF8(FullFileName) then
                    {$ifdef LCL}Debugln{$else}writeln{$endif}('DeleteFileUTF8 says it failed but FileExists says its gone, proceed !')
                else exit(false);
            end;
        end;
    end;
    Result := true;
end;

function RemoveBadXMLCharacters(const InStr : ANSIString; DoQuotes : boolean = false) : ANSIString;
// Don't use UTF8 versions of Copy() and Length(), we are working bytes !
// It appears that Tomboy only processes <, > and & , we also process single and double quote.
// http://xml.silmaril.ie/specials.html
var
   //Res : ANSIString;
   Index : longint = 1;
   Start : longint = 1;
begin
    Result := '';
   while Index <= length(InStr) do begin
   		if InStr[Index] = '<' then begin
             Result := Result + Copy(InStr, Start, Index - Start);
             Result := Result + '&lt;';
             inc(Index);
             Start := Index;
			 continue;
		end;
  		if InStr[Index] = '>' then begin
             Result := Result + Copy(InStr, Start, Index - Start);
             Result := Result + '&gt;';
             inc(Index);
             Start := Index;
			 continue;
		end;
  		if InStr[Index] = '&' then begin
             // debugln('Start=' + inttostr(Start) + ' Index=' + inttostr(Index));
             Result := Result + Copy(InStr, Start, Index - Start);
             Result := Result + '&amp;';
             inc(Index);
             Start := Index;
			 continue;
		end;
        if DoQuotes then begin
      		if InStr[Index] = '''' then begin                // Ahhhh how to escape a single quote ????
                 Result := Result + Copy(InStr, Start, Index - Start);
                 Result := Result + '&apos;';
                 inc(Index);
                 Start := Index;
    			 continue;
    		end;
            if InStr[Index] = '"' then begin
                 Result := Result + Copy(InStr, Start, Index - Start);
                 Result := Result + '&quot;';
                 inc(Index);
                 Start := Index;
                 continue;
		    end;
        end;

        inc(Index);
   end;
   Result := Result + Copy(InStr, Start, Index - Start);
end;

function IDLooksOK(const ID : string) : boolean;
begin
    if length(ID) <> 36 then exit(false);
    if pos('-', ID) <> 9 then exit(false);
    result := True;
end;

function GetNoteLastChangeSt(const FullFileName : string; out Error : string) : string;
var
	Doc : TXMLDocument;
	Node : TDOMNode;
    // LastChange : string;
begin
    if not FileExistsUTF8(FullFileName) then begin
        Error := 'ERROR - File not found, cant read note change date for remote ' +  FullFileName;
        exit('');
	end;
	try
		ReadXMLFile(Doc, FullFileName);
		Node := Doc.DocumentElement.FindNode('last-change-date');
        Result := Node.FirstChild.NodeValue;
	finally
        Doc.free;		// TODO - xml errors are NOT caught in calling process
	end;
end;


{ ----------------  TNoteInfoList ---------------- }


function TNoteInfoList.AddByFileName(FFilename : string; Act : TSyncAction; Rev : integer = 0) : boolean;
var
    pNote : PNoteInfo;
    Doc : TXMLDocument;
    Node : TDOMNode;
begin
    new(pNote);
    try
	        try
	            ReadXMLFile(Doc, FFileName);
	            Node := Doc.DocumentElement.FindNode('title');
	            pNote^.Title := Node.FirstChild.NodeValue;
	            Node := Doc.DocumentElement.FindNode('last-change-date');
	            if assigned(node) then
	                pNote^.LastChange := Node.FirstChild.NodeValue
	            else exit(False);
	            pNote^.LastChangeGMT := GetGMTFromStr(pNote^.LastChange);
	            Node := Doc.DocumentElement.FindNode('create-date');
	            if assigned(node) then
	                pNote^.CreateDate := Node.FirstChild.NodeValue
	            else exit(False);
	            pNote^.ID := copy(FFilename, length(FFilename) - 42, 36);
	            pNote^.Action:= Act;
	            pNote^.SID:=0;
	            pNote^.Rev:=Rev;
	            Add(pNote);
	        except on E: Exception do
	            debugln('Error reading note, ' + E.Message);
	        end;
	finally
	        Doc.free;
	end;
end;

function TNoteInfoList.Add(ANote : PNoteInfo) : integer;
begin
    result := inherited Add(ANote);
end;

{ This will be quite slow with a big list notes, consider an AVLTree ? }
function TNoteInfoList.FindSID(const SID: longint): PNoteInfo;
var
    Index : longint;
begin
    Result := Nil;
    for Index := 0 to Count-1 do begin
        if Items[Index]^.SID = SID then begin
            Result := Items[Index];
            exit()
        end;
    end;
end;

function TNoteInfoList.FindID(const ID: ANSIString): PNoteInfo;
var
    Index : longint;
begin
    Result := Nil;
    for Index := 0 to Count-1 do begin
        if Items[Index]^.ID = ID then begin
            Result := Items[Index];
            exit()
        end;
    end;
end;

function TNoteInfoList.FindID(sid : longint): string;
var
    Index : longint;
begin
    Result := '';
    for Index := 0 to Count-1 do begin
        if Items[Index]^.SID = sid then begin
            Result := Items[Index]^.ID;
            exit()
        end;
    end;
end;

function TNoteInfoList.ActionName(Act: TSyncAction): string;
begin
    Result := ' Unknown ';
    case Act of
        SyUnset : Result := ' Unset ';
        SyNothing : Result := ' Nothing ';
        SyUploadNew  : Result := ' UploadNew ';   // we differentiate in case of a write to remote fail.
        SyUpLoadEdit : Result := ' UpLoadEdit ';
        SyDownload: Result := ' Download ';
        SyDeleteLocal  : Result := ' DeleteLocal ';
        SyDeleteRemote : Result := ' DeleteRemote ';
        SyError : Result := ' ** ERROR **';
        SyClash : Result := ' Clash ';
        SyAllLocal : Result := ' AllLocal ';
        SyAllRemote : Result := ' AllRemote ';
        SyAllNewest : Result := ' AllNewest ';
        SyAllOldest : Result := ' AllOldest ';
    end;
    while length(result) < 15 do Result := Result + ' ';
end;

destructor TNoteInfoList.Destroy;
var
I : integer;
begin
    for I := 0 to Count-1 do
        dispose(Items[I]);
    inherited;
end;

function TNoteInfoList.Get(Index: integer): PNoteInfo;
begin
    Result := PNoteInfo(inherited get(Index));
end;


function GetRevisionDirPath(ServerPath: string; Rev: integer; NoteID : string = ''): string;
begin
    result := appendpathDelim(appendpathdelim(serverPath)
        + inttostr(Rev div 100) + pathDelim + inttostr(rev));
    if NoteID <> '' then
        result := result + NoteID + '.note';
end;

function UsingRightRevisionPath(ServerPath: string; Rev: integer): boolean;
var
    FullDirName : string;
begin
    FullDirname := GetRevisionDirPath(ServerPath, Rev);
    // debugln('Right sync Dir is ' + FullDirName);
    Result :=  DirectoryExists(FullDirName);   // we hope its in 'wrong' place ....
    // Just to be carefull ...
    {FullDirname := appendpathdelim(serverPath) + '0' + pathDelim + inttostr(rev);
    if DirectoryExists(FullDirName) then begin
        debugln('ERROR, Sync Repo has two sync directories for rev no ' + inttostr(rev));
        debugln('We will use ' + GetRevisionDirPath(ServerPath, Rev));
    end; }
    //result := true;
end;

// Takes a normal Tomboy DateTime string and converts it to UTC, ie zero offset
function ConvertDateStrAbsolute(const DateStr : string) : string;
var
    Temp : TDateTime;
begin
    if DateStr = '' then exit('');                // Empty string
    // A date string should look like this -  2018-01-27T17:13:03.1230000+11:00 33 characters !
    // but on Android, its always             2018-01-27T17:13:03.1230000+00:00  ie GMT absolute
    if length(DateStr) <> 33 then begin
        {$ifdef LCL}Debugln{$else}writeln{$endif}('ERROR ConvertDateStrAbsolute received invalid date string - [' + DateStr + ']');
        exit('');
    end;
    Temp := GetGMTFromStr(DateStr) {- GetLocalTimeOffset()};
    Result := FormatDateTime('YYYY-MM-DD',Temp) + 'T'
                   + FormatDateTime('hh:mm:ss.zzz"0000+00:00"',Temp);
end;

{ This function is used if we get a datetime str in UTC format, no time
  zone specified, just a 'Z'. The time is already in GMT.  Gnote gives
  us 6 decimal places after second but we can cope with nany. Must have
  yyyy-mm-ddThh:mm:ssZ and opt .nnn.. between 'ss and 'Z' }
function GetZuluDateTime(const  DateStr: ANSIString): TDateTime;
var
    Tstr : string = '';
    MilliSeconds : TDateTime = 0.0;
    Places : integer;
begin
    result := 0.0;
    if pos('Z', DateStr) < 1 then exit(0);
    if pos('.', DateStr) > 0 then begin                     // we make no assumption about number of decimal places in mSec
        Places := pos('Z', DateStr) - pos('.', DateStr) -1;
        if Places > 3 then Places := 3;
        if Places > 0 then begin
        Tstr := copy(DateStr, pos('.', DateStr)+1, Places);      // note, only 3 places of mSec are read
        if TStr <> '' then
            try
                while Places < 3 do begin TStr := TStr + '0'; inc(Places); end;
                debugln('TStr = ' + TStr);
                if not TryEncodeTimeInterval(0, 0, 0, strtoint(TStr), MilliSeconds) then	// Hour, Min, Sec, mSec, outVar
                    {$ifdef LCL}Debugln{$else}writeln{$endif}('Fail on interval encode ');
            except on EConvertError do begin
    	            {$ifdef LCL}Debugln{$else}writeln{$endif}('FAIL on converting time interval ' + DateStr);
                    {$ifdef LCL}Debugln{$else}writeln{$endif}('Hour ', copy(DateStr, 29, 2), ' minutes ', copy(DateStr, 32, 2));
	            end;
            end;
        end;
    end;
    try
        if not TryEncodeDateTime(
            strtoint(copy(DateStr, 1, 4)),   	        // Year
            strtoint(copy(DateStr, 6, 2)),              // Month
            strtoint(copy(DateStr, 9, 2)),				// Day
            strtoint(copy(DateStr, 12, 2)),				// Hour
            strtoint(copy(DateStr, 15, 2)),				// Minutes
            strtoint(copy(DateStr, 18, 2)),				// Seconds
            0,	Result)  then
                {$ifdef LCL}Debugln{$else}writeln{$endif}('Fail on date time encode ');
    except on EConvertError do begin
        {$ifdef LCL}Debugln{$else}writeln{$endif}('FAIL on converting date time ' + DateStr);
        exit(0.0);
        end;
    end;
    Result := Result + milliSeconds;
end;

function GetGMTFromStr(const DateStr: ANSIString): TDateTime;
var
    TimeZone : TDateTime;
begin
    if DateStr = '' then exit(0);                // Empty string
    // A date string should look like this -     2018-01-27T17:13:03.1230000+11:00 33 characters !
    // But from GNote looks like this            2018-01-27T17:13:03.123000Z 27 char, Zulu time, one less dec second digit, its GMT
    if length(DateStr) <> 33 then begin
        {$ifdef LCL}Debugln{$else}writeln{$endif}('ERROR received invalid date string - [' + DateStr + ']');
        exit(0);
    end;
    try
	    if not TryEncodeTimeInterval( 	strtoint(copy(DateStr, 29, 2)),				// Hour
	    								strtoint(copy(DateStr, 32, 2)),				// Minutes
			        					0,				// Seconds
	                					0,				// mSeconds
	                					TimeZone)  then {$ifdef LCL}Debugln{$else}writeln{$endif}('Fail on interval encode ');
    except on EConvertError do begin
        	{$ifdef LCL}Debugln{$else}writeln{$endif}('FAIL on converting time interval ' + DateStr);
            {$ifdef LCL}Debugln{$else}writeln{$endif}('Hour ', copy(DateStr, 29, 2), ' minutes ', copy(DateStr, 32, 2));
    	end;
    end;
    try
	    if not TryEncodeDateTime(strtoint(copy(DateStr, 1, 4)),   	// Year
	    			strtoint(copy(DateStr, 6, 2)),              // Month
	                strtoint(copy(DateStr, 9, 2)),				// Day
	                strtoint(copy(DateStr, 12, 2)),				// Hour
	                strtoint(copy(DateStr, 15, 2)),				// Minutes
	                strtoint(copy(DateStr, 18, 2)),				// Seconds
	                strtoint(copy(DateStr, 21, 3)),				// mSeconds
	                Result)  then {$ifdef LCL}Debugln{$else}writeln{$endif}('Fail on date time encode ');
    except on EConvertError do begin
        	{$ifdef LCL}Debugln{$else}writeln{$endif}('FAIL on converting date time ' + DateStr);
            exit(0.0);
    	end;
    end;
    try
	    if DateStr[28] = '+' then
            Result := Result - TimeZone
		else if DateStr[28] = '-' then
            Result := Result + TimeZone
	    else {$ifdef LCL}Debugln{$else}writeln{$endif}('******* Bugger, we are not parsing DATE String ********');
    except on EConvertError do begin
        	{$ifdef LCL}Debugln{$else}writeln{$endif}('FAIL on calculating GMT ' + DateStr);
            exit(0.0);
    	end;
    end;
    { writeln('Date is ', DatetoStr(Result), ' ', TimetoStr(Result));  }
end;

function SafeGetUTCfromStr(const DateStr : string; out DateTime : TDateTime; out ErrorMsg : string) : boolean;
begin
    ErrorMsg := '';
    if length(DateStr) = 33 then                // This is the Tomboy standard
        DateTime := GetGMTFromStr(DateStr)
    else if  pos('Z', DateStr) > 0 then
        DateTime := GetZuluDateTime(DateStr)        // Gnote does this
        else begin
            ErrorMsg := 'Date String wrong length';
            DateTime := 0.0;
            exit(False);
        end;
    // if to here, we have at least tried to convert it.
    if DateTime < 1.0 then begin
        ErrorMsg := 'Invalid Date String';
        exit(False);
    end;
    if (DateTime > (now() + 36500)) or (DateTime < (Now() - 36500))  then begin
        ErrorMsg := 'Date beyond expected range';
        DateTime := 0.0;
        exit(False);
    end;
 		// TDateTime has integer part, no. of days, fraction part is fraction of day.
		// 100years ago or in future - Fail !
    exit(True);
end;


function MakeGUID() : string;
var
    GUID : TGUID;
begin
    CreateGUID(GUID);
    Result := copy(GUIDToString(GUID), 2, 36);      // it arrives here wrapped in {}
end;

end.

