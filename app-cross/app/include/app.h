/*
 * SPDX-FileCopyrightText: 2025 Davide De Rosa
 *
 * SPDX-License-Identifier: GPL-3.0
 */

#pragma once
#include <wx/wx.h>
#include <wx/listbox.h>
#include <wx/process.h>
#include <wx/timer.h>

class MyApp : public wxApp
{
public:
    bool OnInit() override;
};

class MyFrame : public wxFrame
{
public:
    MyFrame();

private:
    void OnImportProfile(wxCommandEvent &event);
    void OnAbout(wxCommandEvent &event);
    void OnQuit(wxCommandEvent &event);
    void OnConnect(wxCommandEvent &event);
    void OnDisconnect(wxCommandEvent &event);
    void OnRefreshProfiles(wxCommandEvent &event);
    void OnProfileSelect(wxCommandEvent &event);
    void OnEndProcess(wxProcessEvent &event);
    void OnLogTimer(wxTimerEvent &event);
    void OnABIEvent(wxCommandEvent &event);

    bool EnsureProfilesDir();
    void RefreshProfileList();
    void StartTunnel(const wxString &profilePath);
    void StopTunnel();
    void UpdateStatus();
    void AppendStreamOutput(wxInputStream *stream);

    wxListBox *m_profileList = nullptr;
    wxStaticText *m_statusLabel = nullptr;
    wxTextCtrl *m_logView = nullptr;
    wxButton *m_connectBtn = nullptr;
    wxButton *m_disconnectBtn = nullptr;

    wxProcess *m_tunnelProcess = nullptr;
    long m_tunnelPid = 0;
    wxString m_runningProfilePath;
    bool m_disconnectRequested = false;
    wxString m_profilesDir;
    wxArrayString m_profilePaths;
    wxTimer m_logTimer;
};

enum {
    ID_Connect = 100,
    ID_Disconnect,
    ID_ImportProfile,
    ID_RefreshProfiles
};
