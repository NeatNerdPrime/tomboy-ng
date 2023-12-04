unit SyncGUI;
{    Copyright (C) 2017-2020 David Bannon

    License:
    This code is licensed under BSD 3-Clause Clear License, see file License.txt
    or https://spdx.org/licenses/BSD-3-Clause-Clear.html

    ------------------

}

{	History
	2017/12/06	Marked FileSync debug mode off to quieten console output a little
	2017/12/30  Changed above DebugMode to VerboseMode
	2017/12/30  We now call IndexNotes() after a sync. Potentially slow.
	2017/12/30  Added a seperate procedure to do manual Sync, its called
				by a timer to ensure we can see dialog before it starts.
	2018/01/01  Added ID in sync report to make it easier to track errors.
	2018/01/01  Set goThumbTracking true so contents of scroll box glide past as
    			you move the "Thumb Slide".
	2018/01/01  Changed ModalResult for cancel button to mrCancel
	2018/01/08  Tidied up message box text displayed when a sync conflict happens.
	2018/01/25  Changes to support Notebooks
    2018/01/04  Forced a screen update before manual sync so user knows whats happening.
    2018/04/12  Added ability to call MarkNoteReadOnly() to cover case where user has unchanged
                note open while sync process downloads or deletes that note from disk.
    2018/04/13  Taught MarkNoteReadOnly() to also delete ref in NoteLister to a sync deleted note
    2018/05/12  Extensive changes - MainUnit is now just that. Only change here relates
                to naming of MainUnit and SearchUnit.
    2018/05/21  Show any sync errors as hints in the StringGrid.
    2018/06/02  Honor a cli --debug-sync
    2018/06/14  Update labels when transitioning from Testing Sync to Manual Sync
    2018/08/14  Added SDiff to replace clumbsy dialog when sync clash happens.
    2018/08/18  Improved test/reporting of file access during sync
    2018/10/25  New sync model. Much testing, support for Tomdroid.
    2018/10/28  Much tweaking and bug fixing.
    2018/10/29  Tell TB_Sdiff about note title before showing it.
    2018/10/30  Don't show SyNothing in sync report
    2018/11/04  Added support to update in memory NoteList after a sync.
    2019/05/19  Display strings all (?) moved to resourcestrings
    2020/02/20  Added capability to sync without showing GUI.
    2020/06/18  Only show good sync notification for 3 seconds
    2020/08/07  Changed the stringGrid to a ListView 'cos it handles dark themes better.
    2020/08/10  ListView becomes type=vsReport
    2020/04/26  Set Save button to disabled immediatly when pressed.
    2021/09/08  Added progress indicator
    2022/04/15  Improve man sync close button communication with user.
}

{$mode objfpc}{$H+}




interface

uses
		Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, ExtCtrls,
		StdCtrls, {Grids,} ComCtrls, Syncutils;

type

		{ TFormSync }

  TFormSync = class(TForm)
				ButtonSave: TButton;
				ButtonCancel: TButton;
				ButtonClose: TButton;
				Label1: TLabel;
				Label2: TLabel;
                LabelProgress: TLabel;
                ListViewReport: TListView;      // Viewstyle=vsReport, make columns in Object Inspector
				Memo1: TMemo;
				Panel1: TPanel;
				Panel2: TPanel;
				Panel3: TPanel;
				Splitter3: TSplitter;
                                        { Runs a sync without showing form. Ret False if error or its not setup.
                                          Caller must ensure that Sync is config and that the Sync dir is available.
                                          If clash, user will see dialog. }
                procedure FormCreate(Sender: TObject);
//                function RunSyncHidden() : boolean;
				procedure ButtonCancelClick(Sender: TObject);
				procedure ButtonCloseClick(Sender: TObject);
    			procedure ButtonSaveClick(Sender: TObject);
				procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
                procedure FormHide(Sender: TObject);
                { At Show, depending on SetUpSync, we'll either go ahead and do it, any
                  error is fatal or, if True, walk user through process. }
				procedure FormShow(Sender: TObject);
		private
                FormShown : boolean;
                LocalTimer : TTimer;

                procedure AddLVItem(Act, Title, ID: string);
                procedure AdjustNoteList();
                procedure AfterShown(Sender : TObject);
                    // Display a summary of sync actions to user.
                function DisplaySync(): string;
                    { Called when user wants to join a (possibly uninitialised) Repo,
                      will handle some problems with user's help. }
                procedure JoinSync;
                    { Called to do a sync assuming its all setup. Any problem is fatal }
                function ManualSync: boolean;
                    { Populates the string grid with details of notes to be actioned }
                procedure ShowReport;

                                    { We will pass address of this method to lower level units so
                                    they can report on progress. Short one to three words ?  }
                procedure SyncProgress(const St: string);

		public
                Busy : boolean; // indicates that there is some sort of sync in process now.
                AnotherSync : boolean;  // After this (manual) sync, we have another one (ie github)
                Transport : TSyncTransPort;
                UserName, Password : string;    // For those thatnsports that need such things.
                LocalConfig, NoteDirectory : ANSIString;
                    { Indicates we are doing a setup User has already agreed to abandon any
                      existing Repo but we don't know if indicated spot already contains a
                      repo or, maybe we want to make one. }
              	SetupSync : boolean;
                    { we will pass address of this function to Sync }
                function Proceed(const ClashRec : TClashRecord) : TSyncAction;
		end;

var
		FormSync: TFormSync;

implementation

{ In SetupFileSync mode, does a superficial, non writing, test OnShow() user
  can then click 'OK' and we'd do a real sync, exit and settings saved in calling
  process.
}

uses LazLogger, SearchUnit, TB_SDiff, Sync,  LCLType, {SyncError,} ResourceStr,
        {notifier,} Settings, MainUnit { tb_utils};

{$R *.lfm}

var
        ASync : TSync;
{ TFormSync }


function TFormSync.Proceed(const ClashRec : TClashRecord) : TSyncAction;
var
    SDiff : TFormSDiff;
begin
    SDiff := TFormSDiff.Create(self);
    SDiff.RemoteFilename := ClashRec.ServerFileName;
    SDiff.LocalFilename := ClashRec.LocalFileName;
    SDiff.NoteTitle := ClashRec.Title;
    case SDiff.ShowModal of
            mrYes      : Result := SyDownLoad;
            mrNo       : Result := SyUpLoadEdit;
            mrNoToAll  : Result := SyAllLocal;
            mrYesToAll : Result := SyAllRemote;
            mrAll      : Result := SyAllNewest;
            mrClose    : Result := SyAllOldest;
    otherwise
            Result := SyUnSet;      // Thats an ERROR !  What are you doing about it ?
    end;
    SDiff.Free;
    Application.ProcessMessages;    // so dialog goes away while remainder are being processed.
    // Use Remote, Yellow is mrYes, File1
    // Use Local, Aqua is mrNo, File2
end;

procedure TFormSync.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
	FreeandNil(ASync);
    Busy := False;
end;

procedure TFormSync.FormHide(Sender: TObject);
begin
    if LocalTimer = Nil then exit();
    LocalTimer.Free;
    LocalTimer := nil;
end;

procedure TFormSync.SyncProgress(const St: string);
begin
        LabelProgress.Caption := St;
        Application.ProcessMessages;
end;

// Following resourcestrings defined in syncUtils.pas

function TFormSync.DisplaySync(): string;
var
    UpNew, UpEdit, Down, DelLoc, DelRem, Clash, DoNothing, Errors : integer;
begin
    ASync.ReportMetaData(UpNew, UpEdit, Down, DelLoc, DelRem, Clash, DoNothing, Errors);
    Memo1.Append(rsNewUploads + inttostr(UpNew));
    Memo1.Append(rsEditUploads + inttostr(UpEdit));
    Memo1.Append(rsDownloads + inttostr(Down));
    Memo1.Append(rsLocalDeletes + inttostr(DelLoc));
    Memo1.Append(rsRemoteDeletes + inttostr(DelRem));
    Memo1.Append(rsClashes + inttostr(Clash));
    Memo1.Append(rsDoNothing + inttostr(DoNothing));
    if Errors > 0 then
        Memo1.Append(rsSyncERRORS + inttostr(Errors));
    result := 'Uploads=' + inttostr(UpNew+UpEdit) + ' downloads=' + inttostr(Down) + ' deletes=' + inttostr(DelLoc + DelRem);
    // debugln('Display Sync called, DoNothings is ' + inttostr(DoNothing));
end;

    // User is only allowed to press Cancel or Save when this is finished.
procedure TFormSync.JoinSync;
var
    SyncAvail : TSyncAvailable;
begin
    freeandnil(ASync);
    ASync := TSync.Create;
    Label1.Caption :=  SyncTransportName(Transport) + ' ' + rsTestingRepo;
    Application.ProcessMessages;
    ASync.ProceedFunction:= @Proceed;
    ASync.DebugMode := Application.HasOption('s', 'debug-sync');
    ASync.NotesDir:= NoteDirectory;
    ASync.ConfigDir := LocalConfig;
    ASync.ProgressProcedure := @SyncProgress;
    ASync.Password := Sett.LabelToken.Caption;              // better find a better way to do this Davo
    Async.UserName := Sett.EditUserName.text;
    ASync.RepoAction:=RepoJoin;
    Async.SetTransport(TransPort);
    SyncAvail := ASync.TestConnection();
    if SyncAvail = SyncNoRemoteRepo then
        if mrYes = QuestionDlg('Advice', rsCreateNewRepo, mtConfirmation, [mrYes, mrNo], 0) then begin
            ASync.RepoAction:=RepoNew;
            SyncAvail := ASync.TestConnection();
        end;
    if SyncAvail <> SyncReady then begin
        showmessage(rsUnableToProceed + ' ' + ASync.ErrorString);
        ModalResult := mrCancel;
    end;
    Label1.Caption :=  SyncTransportName(Transport) + ' ' + rsLookingatNotes;
    Application.ProcessMessages;
    ASync.TestRun := True;
    ASync.GetSyncData();                    // does not return anything interesting here. Does in Auto mode however.
//    if  ASync.UseSyncData() then begin  // ToDo : am I dealing with TestRun correctly ?
        DisplaySync();
        ShowReport();
        Label1.Caption :=  SyncTransportName(Transport) + ' ' + rsLookingatNotes;
        Label2.Caption := rsSaveAndSync;
        ButtonSave.Enabled := True;
//    end  else
//        Showmessage(rsSyncError + ' ' + ASync.ErrorString);
    ButtonCancel.Enabled := True;
end;

procedure TFormSync.AfterShown(Sender : TObject);
begin
    LocalTimer.Enabled := False;             // Don't want to hear from you again
    if SetUpSync then begin
        JoinSync();
    end else
        ManualSync();
end;

//RESOURCESTRING
//  rsPleaseWait = 'Please wait a minute or two ...';

procedure TFormSync.FormShow(Sender: TObject);
begin
    if Application.HasOption('debug-sync') then
        debugln('TFormSync.FormShow ');
    Busy := True;
    LabelProgress.Caption := '';
    Left := 55 + random(55);
    Top := 55 + random(55);
    FormShown := False;
    Label2.Caption := rsNextBitSlow;
    Memo1.Clear;
    ListViewReport.Clear;
    ButtonSave.Enabled := False;
    ButtonClose.Enabled := False;
    ButtonCancel.Enabled := False;
    {$ifdef windows}  // linux apps know how to do this themselves
    if Sett.DarkTheme then begin
         // Sett.BackGndColour;  Sett.TextColour;
         ListViewReport.Color :=       clnavy;
         ListViewReport.Font.Color :=  Sett.HiColour;
         splitter3.Color:= clnavy;
         Panel1.color := Sett.BackGndColour;
         Panel2.color := Sett.BackGndColour;
         Panel3.color := Sett.BackGndColour;
         Label1.Font.Color:= Sett.TextColour;
         Label2.Font.Color := Sett.TextColour;
         Memo1.Color:= Sett.BackGndColour;
         Memo1.Font.Color := Sett.TextColour;
         ButtonCancel.Color := Sett.HiColour;
         ButtonClose.Color := Sett.HiColour;
         ButtonSave.Color := Sett.HiColour;
    end;
    {$endif}
    // We call a timer to get out of OnShow so ProcessMessages works as expected
    LocalTimer := TTimer.Create(Nil);
    LocalTimer.OnTimer:= @AfterShown;
    LocalTimer.Interval:=500;
    LocalTimer.Enabled := True;
end;

(* function TFormSync.RunSyncHidden(): boolean;          // ToDo : this is now done in Settings, remove ???
begin
    //debugln('In RunSyncHidden');
    if SetUpSync then exit(False);      // should never call this in setup mode but to be sure ...
    busy := true;
    ListViewReport.Clear;
    // Result := ManualSync();
    ASync := TSync.Create;
    try
        ASync.AutoSetUp(Transport);             // ToDo : must determine what mode of Sync we are running in.
        ASync.GetSyncData();
        ASync.UseSyncData();
    finally
        ASync.Free;
        Busy := False;
    end;
end; *)

procedure TFormSync.FormCreate(Sender: TObject);
begin
    UserName := '';
    Password := '';
end;

        // User is only allowed to press Close when this is finished.
function TFormSync.ManualSync : boolean;
var
    //SyncState : TSyncAvailable = SyncNotYet;
    //Notifier : TNotifier;
    SyncSummary : string;
begin
    Label1.Caption :=  SyncTransportName(Transport) + ' ' + rsTestingSync;
    Application.ProcessMessages;
	ASync := TSync.Create;
    try
        //Screen.Cursor := crHourGlass;
        //sleep(1000);
        ASync.ProceedFunction := @Proceed;
        ASync.ProgressProcedure := @SyncProgress;
        ASync.DebugMode := Application.HasOption('s', 'debug-sync');
	    ASync.NotesDir:= NoteDirectory;
	    ASync.ConfigDir := LocalConfig;
        ASync.RepoAction:= RepoUse;
        ASync.Password := Sett.LabelToken.Caption;              // better find a better way to do this Davo
        Async.UserName := Sett.EditUserName.text;
        Async.SetTransport(TransPort);
//debugln({$I %FILE%}, ', ', {$I %CURRENTROUTINE%}, '(), line:', {$I %LINE%}, ' : Testing Connection.');
        if ASync.TestConnection() <> SyncReady then begin
            debugln({$I %FILE%}, ', ', {$I %CURRENTROUTINE%}, '(), line:', {$I %LINE%}, ' : ', 'Test Transport Failed.');
            if ASync.DebugMode then debugln('Failed testConnection');
            // in autosync mode, form is not visible, we just send a notify that cannot sync right now.and return false
            if not Visible then begin
                SearchForm.UpdateStatusBar(1, rsAutoSyncNotPossible);
                if Sett.CheckNotifications.checked then begin
                    MainForm.ShowNotification(rsAutoSyncNotPossible);
                end;
                exit(false);
            end else begin                                                      // busy unset in finally clause
                //Screen.Cursor := crDefault;
                showmessage('Unable to sync because ' + ASync.ErrorString);
                //Screen.Cursor := crHourGlass;
                FormSync.ModalResult := mrAbort;
                exit(false);                                                    // busy unset in finally clause
            end;
            exit(false);        //redundant ?
        end;
//debugln({$I %FILE%}, ', ', {$I %CURRENTROUTINE%}, '(), line:', {$I %LINE%}, ' : ', 'Transport good, about to run.');
        Label1.Caption :=  SyncTransportName(Transport) + ' ' + rsRunningSync;
        Application.ProcessMessages;
        ASync.TestRun := False;
        if ASync.GetSyncData() and ASync.UseSyncData() then;   // ToDo : should I evaluate separetly ?

        SyncSummary :=  DisplaySync();
        SearchForm.UpdateStatusBar(1, rsLastSync + ' ' + FormatDateTime('YYYY-MM-DD hh:mm', now)  + ' ' + SyncSummary);
        if (not Visible) and Sett.CheckNotifications.Checked then begin
            MainForm.ShowNotification(rsLastSync  + ' ' + SyncSummary, 2000);
        end;
        ShowReport();
        AdjustNoteList();                              // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        Label1.Caption :=  SyncTransportName(Transport) + ' ' + rsAllDone;
        Label2.Caption := rsPressClose;
        ButtonClose.Enabled := True;
        if AnotherSync then begin
            ButtonClose.Hint := 'proceed to next sync';
            ButtonClose.ShowHint := True;
        end else
            ButtonClose.ShowHint := False;
        Result := True;
    finally
        FreeandNil(ASync);
        Busy := False;
        //Screen.Cursor := crDefault;
    end;
end;

procedure TFormSync.AdjustNoteList();
var
    DeletedList, DownList : TStringList;
    Index : integer;
begin
    DeletedList := TStringList.Create;
    DownList := TStringList.Create;
 	with ASync.RemoteMetaData do begin
		for Index := 0 to Count -1 do begin
            if Items[Index]^.Action = SyDeleteLocal then
                DeletedList.Add(Items[Index]^.ID);
            if Items[Index]^.Action = SyDownload then
                DownList.Add(Items[Index]^.ID);
        end;
    end;
    if (DeletedList.Count > 0) or (DownList.Count > 0) then
        SearchForm.ProcessSyncUpdates(DeletedList, DownList);
    FreeandNil(DeletedList);
    FreeandNil(DownList);
end;

procedure TFormSync.AddLVItem(Act, Title, ID : string);
var
    TheItem : TListItem;
begin
   TheItem := ListViewReport.Items.Add;
   TheItem.Caption := Act;
   TheItem.SubItems.Add(copy(Title, 1, 25)+' ');
   TheItem.SubItems.Add(ID);
end;

procedure TFormSync.ShowReport;
var
    Index : integer;
    Rows : integer = 0;
begin
    with ASync.RemoteMetaData do begin
	    for Index := 0 to Count -1 do begin
	        if Items[Index]^.Action <> SyNothing then begin
	                AddLVItem(
	                    ASync.RemoteMetaData.ActionName(Items[Index]^.Action)
	                    , Items[Index]^.Title
	                    , Items[Index]^.ID);
	                inc(Rows);
	        end;
	    end
	end;
	if  Rows = 0 then
	    Memo1.Append(rsNoNotesNeededSync)
	else Memo1.Append(inttostr(ASync.RemoteMetaData.Count) + rsNotesWereDealt);
    if ASync.TransMode = SyncGitHub then begin
        Memo1.Append('Token expires : ' + ASync.TokenExpire);
        Sett.LabelToken.Hint := 'Expires ' + ASync.TokenExpire;
    end;
    {$IFDEF DARWIN}     // Apparently ListView.columns[n].autosize does not work in Mac, this is rough but better then nothing.
    ListViewReport.Columns[0].Width := listviewReport.Canvas.Font.GetTextWidth('upload edit ');
    ListViewReport.Columns[1].Width := ListViewReport.Columns[0].Width *2;
    {$ENDIF}
end;


procedure TFormSync.ButtonCancelClick(Sender: TObject);
begin
    ModalResult := mrCancel;
end;

procedure TFormSync.ButtonCloseClick(Sender: TObject);
begin
	ModalResult := mrOK;
end;

    // This only ever happens during a Join, RepoAction will still be 'join'.
procedure TFormSync.ButtonSaveClick(Sender: TObject);
begin
    Label2.Caption:=rsNextBitSlow;
    Label1.Caption :=  SyncTransportName(Transport) + ' ' + 'First Time Sync';
    Memo1.Clear;
    ButtonCancel.Enabled := False;
    ButtonSave.Enabled := False;
    Application.ProcessMessages;
    ASync.TestRun := False;
    if ASync.GetSyncData() and ASync.UseSyncData() then begin  // ToDo : should I evaluate separetly ?
        SearchForm.UpdateStatusBar(1, rsLastSync + ' ' + FormatDateTime('YYYY-MM-DD hh:mm', now)  + ' ' + DisplaySync());
        ShowReport();
        AdjustNoteList();
        Label1.Caption :=  SyncTransportName(Transport) + ' ' + rsAllDone;
        Label2.Caption := rsPressClose;
        if ASync.TransMode = SyncGithub then begin
            Sett.LabelSyncRepo.Caption := ASync.GetTransRemoteAddress;   // this relies on Sett being in Github mode, during a Join, should be ....
            Sett.LabelToken.Hint := 'Expires ' + ASync.TokenExpire;
        end;
    end  else
        Showmessage(rsSyncError + ASync.ErrorString);
    ButtonClose.Enabled := True;
end;

end.

