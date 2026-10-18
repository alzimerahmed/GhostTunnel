/*
 * SPDX-FileCopyrightText: 2025 Davide De Rosa
 *
 * SPDX-License-Identifier: GPL-3.0
 */

#include "app.h"
#include "abi.h"

#include <wx/dir.h>
#include <wx/filename.h>
#include <wx/stdpaths.h>

extern "C" {
#include <stdlib.h>
#include "partout.h"
}

namespace {

/*
 * The tunnel binary (ghosttunnel-tunnel) takes the path to a profile JSON
 * file and runs the VPN daemon until killed. The desktop app manages
 * profiles as files under ~/.ghosttunnel/profiles and shells out to the
 * tunnel binary. It cannot query tunnel state beyond process lifecycle,
 * so the status view is honest about that: "Running" means the tunnel
 * process is alive, nothing more.
 */
wxString TunnelExecutablePath() {
    const wxString exePath = wxStandardPaths::Get().GetExecutablePath();
    const wxFileName exeFile(exePath);
    return exeFile.GetPathWithSep() + "ghosttunnel-tunnel";
}

wxString QuoteArg(const wxString &arg) {
    wxString out;
    out += '"';
    for (size_t i = 0; i < arg.length(); ++i) {
        const wxChar c = arg[i];
        if (c == '"' || c == '\\') {
            out += '\\';
        }
        out += c;
    }
    out += '"';
    return out;
}

void AppendStreamOutput(wxTextCtrl *log, wxInputStream *stream) {
    if (!stream) return;
    char buf[4096];
    while (stream->CanRead()) {
        stream->Read(buf, sizeof(buf));
        const size_t n = stream->LastRead();
        if (n == 0) break;
        log->AppendText(wxString::FromUTF8(buf, n));
    }
    // Bound the log view: a long-running tunnel would otherwise grow the
    // control without limit. Trim the oldest half once past the cap.
    const wxTextPos cap = 512 * 1024;
    const wxTextPos len = log->GetLastPosition();
    if (len > cap) {
        log->Remove(0, len - cap / 2);
    }
}

} // namespace

bool MyApp::OnInit()
{
#ifdef _WIN32
    // Per-monitor DPI awareness (v2)
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
#endif

    MyFrame* frame = new MyFrame();
    frame->Show(true);
    return true;
}

MyFrame::MyFrame()
    : wxFrame(nullptr, wxID_ANY, "GhostTunnel")
{
    wxMenuBar* menuBar = new wxMenuBar;

    // Application menu (macOS merges this under the app name)
    wxMenu* appMenu = new wxMenu;
    appMenu->Append(wxID_ABOUT, "&About");
    appMenu->Append(wxID_EXIT, "Quit");

    wxMenu* actionsMenu = new wxMenu;
    actionsMenu->Append(ID_ImportProfile, "&Import profile");
    actionsMenu->Append(ID_RefreshProfiles, "&Refresh profiles");
    const wxString partoutVersion = wxString::Format("Partout %s", partout_version());
    actionsMenu->Append(wxID_ANY, partoutVersion);

    // macOS expects the first menu to be the App menu
    menuBar->Append(appMenu, "App");
    menuBar->Append(actionsMenu, "Actions");

    SetMenuBar(menuBar);

    // Timer events need an owner to reach the frame's Bind below.
    m_logTimer.SetOwner(this);

    m_statusLabel = new wxStaticText(this, wxID_ANY, "Stopped");
    m_profileList = new wxListBox(this, wxID_ANY);
    m_connectBtn = new wxButton(this, ID_Connect, "Connect");
    m_disconnectBtn = new wxButton(this, ID_Disconnect, "Disconnect");
    m_logView = new wxTextCtrl(this, wxID_ANY, "",
        wxDefaultPosition, wxDefaultSize,
        wxTE_MULTILINE | wxTE_READONLY | wxTE_DONTWRAP);

    wxBoxSizer* topSizer = new wxBoxSizer(wxVERTICAL);
    topSizer->Add(m_statusLabel, 0, wxALL, 8);
    topSizer->Add(new wxStaticText(this, wxID_ANY, "Profiles"), 0, wxLEFT | wxRIGHT, 8);
    topSizer->Add(m_profileList, 1, wxLEFT | wxRIGHT | wxBOTTOM | wxEXPAND, 8);

    wxBoxSizer* btnSizer = new wxBoxSizer(wxHORIZONTAL);
    btnSizer->Add(m_connectBtn, 0, wxRIGHT, 4);
    btnSizer->Add(m_disconnectBtn, 0, wxLEFT, 4);
    topSizer->Add(btnSizer, 0, wxLEFT | wxRIGHT | wxBOTTOM, 8);

    topSizer->Add(new wxStaticText(this, wxID_ANY, "Tunnel log"), 0, wxLEFT | wxRIGHT, 8);
    topSizer->Add(m_logView, 2, wxLEFT | wxRIGHT | wxBOTTOM | wxEXPAND, 8);

    SetSizer(topSizer);

    Bind(wxEVT_MENU, &MyFrame::OnImportProfile, this, ID_ImportProfile);
    Bind(wxEVT_MENU, &MyFrame::OnRefreshProfiles, this, ID_RefreshProfiles);
    Bind(wxEVT_MENU, &MyFrame::OnAbout, this, wxID_ABOUT);
    Bind(wxEVT_MENU, &MyFrame::OnQuit, this, wxID_EXIT);
    Bind(wxEVT_BUTTON, &MyFrame::OnConnect, this, ID_Connect);
    Bind(wxEVT_BUTTON, &MyFrame::OnDisconnect, this, ID_Disconnect);
    Bind(wxEVT_LISTBOX, &MyFrame::OnProfileSelect, this);
    Bind(wxEVT_END_PROCESS, &MyFrame::OnEndProcess, this);
    Bind(wxEVT_TIMER, &MyFrame::OnLogTimer, this);
    Bind(wxEVT_ABI_EVENT, &MyFrame::OnABIEvent, this);

    EnsureProfilesDir();
    RefreshProfileList();
    UpdateStatus();

    SetSize(560, 480);
    Centre();
}

bool MyFrame::EnsureProfilesDir()
{
    const wxChar sep = wxFileName::GetPathSeparator();
    const wxString gtDir = wxGetHomeDir() + sep + ".ghosttunnel";
    m_profilesDir = gtDir + sep + "profiles";
    if (!wxDirExists(gtDir) && !wxMkdir(gtDir)) {
        wxLogError("Unable to create profiles directory: %s", gtDir);
        return false;
    }
    if (!wxDirExists(m_profilesDir) && !wxMkdir(m_profilesDir)) {
        wxLogError("Unable to create profiles directory: %s", m_profilesDir);
        return false;
    }
    return true;
}

void MyFrame::RefreshProfileList()
{
    m_profileList->Clear();
    m_profilePaths.Clear();

    wxArrayString files;
    wxDir::GetAllFiles(m_profilesDir, &files, "*.json", wxDIR_FILES);
    files.Sort();

    for (const wxString &path : files) {
        m_profilePaths.Add(path);
        m_profileList->Append(wxFileName(path).GetFullName());
    }
    UpdateStatus();
}

void MyFrame::UpdateStatus()
{
    if (m_tunnelPid != 0) {
        const wxString name = m_runningProfilePath.IsEmpty()
            ? "?"
            : wxFileName(m_runningProfilePath).GetFullName();
        m_statusLabel->SetLabel(wxString::Format("Running: %s (tunnel process alive)", name));
        m_connectBtn->Disable();
        m_disconnectBtn->Enable();
    } else {
        m_statusLabel->SetLabel(wxString::Format("Stopped (%zu profile(s))", m_profilePaths.size()));
        m_connectBtn->Enable(m_profileList->GetSelection() >= 0);
        m_disconnectBtn->Disable();
    }
}

void MyFrame::OnImportProfile(wxCommandEvent &)
{
    wxFileDialog openDialog(this, "Import profile",
        m_profilesDir, "",
        "Profile files (*.ovpn;*.conf;*.json)|*.ovpn;*.conf;*.json",
        wxFD_OPEN | wxFD_FILE_MUST_EXIST);

    if (openDialog.ShowModal() == wxID_CANCEL) return;

    const wxString srcPath = openDialog.GetPath();
    const wxString destPath = m_profilesDir
        + wxFileName::GetPathSeparator()
        + wxFileName(srcPath).GetFullName();
    if (!wxCopyFile(srcPath, destPath, true)) {
        wxLogError("Unable to copy profile to: %s", destPath);
        return;
    }
    RefreshProfileList();
}

void MyFrame::OnRefreshProfiles(wxCommandEvent &)
{
    RefreshProfileList();
}

void MyFrame::OnProfileSelect(wxCommandEvent &)
{
    UpdateStatus();
}

void MyFrame::OnConnect(wxCommandEvent &)
{
    if (m_tunnelPid != 0) return;
    const int sel = m_profileList->GetSelection();
    if (sel < 0 || (size_t)sel >= m_profilePaths.size()) return;

    const wxString tunnelExe = TunnelExecutablePath();
    if (!wxFileExists(tunnelExe)) {
        wxLogError("Tunnel binary not found next to the app: %s", tunnelExe);
        return;
    }

    StartTunnel(m_profilePaths[sel]);
}

void MyFrame::StartTunnel(const wxString &profilePath)
{
    const wxString tunnelExe = TunnelExecutablePath();
    const wxString cmd = QuoteArg(tunnelExe) + " " + QuoteArg(profilePath);

    m_disconnectRequested = false;
    m_tunnelProcess = new wxProcess(this, wxID_ANY, true);
    const long pid = wxExecute(cmd, wxEXEC_ASYNC, m_tunnelProcess);
    if (pid <= 0) {
        wxLogError("Unable to launch tunnel binary: %s", tunnelExe);
        delete m_tunnelProcess;
        m_tunnelProcess = nullptr;
        return;
    }
    m_tunnelPid = pid;
    m_runningProfilePath = profilePath;
    m_logView->AppendText(wxString::Format(
        "[app] launched tunnel (pid %ld): %s\n", pid, wxFileName(profilePath).GetFullName()));
    m_logTimer.Start(200);
    UpdateStatus();
}

void MyFrame::OnDisconnect(wxCommandEvent &)
{
    if (m_tunnelPid == 0) return;
    StopTunnel();
}

void MyFrame::StopTunnel()
{
    m_disconnectRequested = true;
    m_logView->AppendText("[app] disconnecting (SIGTERM)\n");
    wxKill(m_tunnelPid, wxSIGTERM);
}

void MyFrame::OnEndProcess(wxProcessEvent &)
{
    // We process wxEVT_END_PROCESS, so per wxProcess docs we own the object.
    if (m_tunnelProcess) {
        // Drain whatever the tunnel printed before it exited.
        AppendStreamOutput(m_logView, m_tunnelProcess->GetInputStream());
        AppendStreamOutput(m_logView, m_tunnelProcess->GetErrorStream());
        delete m_tunnelProcess;
        m_tunnelProcess = nullptr;
    }
    m_logTimer.Stop();
    m_logView->AppendText("[app] tunnel process ended\n");
    m_tunnelPid = 0;
    m_runningProfilePath.Clear();
    const bool wasDisconnectRequested = m_disconnectRequested;
    m_disconnectRequested = false;
    UpdateStatus();
    m_statusLabel->SetLabel(wasDisconnectRequested
        ? "Disconnected"
        : "Stopped (tunnel exited unexpectedly)");
}

void MyFrame::OnLogTimer(wxTimerEvent &)
{
    if (!m_tunnelProcess) return;
    AppendStreamOutput(m_logView, m_tunnelProcess->GetInputStream());
    AppendStreamOutput(m_logView, m_tunnelProcess->GetErrorStream());
}

void MyFrame::OnAbout(wxCommandEvent &)
{
    wxMessageBox(wxString::Format(
        "GhostTunnel desktop client (MVP).\nConnect/disconnect via the GhostTunnel tunnel binary.\nPartout %s",
        partout_version()),
        "About GhostTunnel", wxOK | wxICON_INFORMATION);
}

void MyFrame::OnQuit(wxCommandEvent &)
{
    if (m_tunnelPid != 0) {
        // The frame is about to die; detach so the process object
        // self-deletes on termination instead of notifying a dead parent.
        if (m_tunnelProcess) {
            m_tunnelProcess->Detach();
            m_tunnelProcess = nullptr;
        }
        StopTunnel();
    }
    Close(true);
}

void MyFrame::OnABIEvent(wxCommandEvent &event)
{
    const wxString json = event.GetString();
    m_logView->AppendText("[abi] " + json + "\n");
}
