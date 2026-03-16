{
  config,
  pkgs,
  lib,
  username,
  ...
}:

let
  sig = "Mvh Erik Frankling";
in
{
  # Install package directly — bypassing programs.thunderbird module to get full user.js control
  home.packages = [ pkgs.thunderbird ];

  home.file.".thunderbird/profiles.ini".force = true;
  home.file.".thunderbird/profiles.ini".text = ''
    [General]
    StartWithLastProfile=1
    Version=2

    [Profile0]
    Default=1
    IsRelative=1
    Name=default
    Path=default
  '';

  home.file.".thunderbird/default/user.js".text = ''
    // Thunderbird declarative config — managed by home-manager

    user_pref("mail.accountmanager.accounts", "account_frankling,account_gmail1,account_gmail2,account_kth,account_outlook");
    user_pref("mail.accountmanager.defaultaccount", "account_frankling");
    user_pref("mail.smtpservers", "smtp_frankling,smtp_gmail1,smtp_gmail2,smtp_kth,smtp_outlook");
    user_pref("mail.smtp.defaultserver", "smtp_frankling");

    // ===== Frankling — erik.frankling@frankling.se (Office 365, OAuth2) =====
    user_pref("mail.account.account_frankling.identities", "id_frankling");
    user_pref("mail.account.account_frankling.server", "server_frankling");
    user_pref("mail.identity.id_frankling.fullName", "Erik Frankling");
    user_pref("mail.identity.id_frankling.useremail", "erik.frankling@frankling.se");
    user_pref("mail.identity.id_frankling.valid", true);
    user_pref("mail.identity.id_frankling.smtpServer", "smtp_frankling");
    user_pref("mail.identity.id_frankling.htmlSigText", "${sig}");
    user_pref("mail.identity.id_frankling.sig_bottom", false);
    user_pref("mail.server.server_frankling.type", "imap");
    user_pref("mail.server.server_frankling.hostname", "outlook.office365.com");
    user_pref("mail.server.server_frankling.port", 993);
    user_pref("mail.server.server_frankling.socketType", 3);
    user_pref("mail.server.server_frankling.userName", "erik.frankling@frankling.se");
    user_pref("mail.server.server_frankling.authMethod", 10);
    user_pref("mail.server.server_frankling.login_at_startup", true);
    user_pref("mail.smtpserver.smtp_frankling.hostname", "smtp.office365.com");
    user_pref("mail.smtpserver.smtp_frankling.port", 587);
    user_pref("mail.smtpserver.smtp_frankling.try_ssl", 2);
    user_pref("mail.smtpserver.smtp_frankling.username", "erik.frankling@frankling.se");
    user_pref("mail.smtpserver.smtp_frankling.authMethod", 10);

    // ===== Gmail 1 — ef.pro454@gmail.com (OAuth2) =====
    user_pref("mail.account.account_gmail1.identities", "id_gmail1");
    user_pref("mail.account.account_gmail1.server", "server_gmail1");
    user_pref("mail.identity.id_gmail1.fullName", "Erik Frankling");
    user_pref("mail.identity.id_gmail1.useremail", "ef.pro454@gmail.com");
    user_pref("mail.identity.id_gmail1.valid", true);
    user_pref("mail.identity.id_gmail1.smtpServer", "smtp_gmail1");
    user_pref("mail.identity.id_gmail1.htmlSigText", "${sig}");
    user_pref("mail.identity.id_gmail1.sig_bottom", false);
    user_pref("mail.server.server_gmail1.type", "imap");
    user_pref("mail.server.server_gmail1.hostname", "imap.gmail.com");
    user_pref("mail.server.server_gmail1.port", 993);
    user_pref("mail.server.server_gmail1.socketType", 3);
    user_pref("mail.server.server_gmail1.userName", "ef.pro454@gmail.com");
    user_pref("mail.server.server_gmail1.authMethod", 10);
    user_pref("mail.server.server_gmail1.is_gmail", true);
    user_pref("mail.server.server_gmail1.login_at_startup", true);
    user_pref("mail.smtpserver.smtp_gmail1.hostname", "smtp.gmail.com");
    user_pref("mail.smtpserver.smtp_gmail1.port", 587);
    user_pref("mail.smtpserver.smtp_gmail1.try_ssl", 2);
    user_pref("mail.smtpserver.smtp_gmail1.username", "ef.pro454@gmail.com");
    user_pref("mail.smtpserver.smtp_gmail1.authMethod", 10);

    // ===== Gmail 2 — erik.frankling@gmail.com (OAuth2) =====
    user_pref("mail.account.account_gmail2.identities", "id_gmail2");
    user_pref("mail.account.account_gmail2.server", "server_gmail2");
    user_pref("mail.identity.id_gmail2.fullName", "Erik Frankling");
    user_pref("mail.identity.id_gmail2.useremail", "erik.frankling@gmail.com");
    user_pref("mail.identity.id_gmail2.valid", true);
    user_pref("mail.identity.id_gmail2.smtpServer", "smtp_gmail2");
    user_pref("mail.identity.id_gmail2.htmlSigText", "${sig}");
    user_pref("mail.identity.id_gmail2.sig_bottom", false);
    user_pref("mail.server.server_gmail2.type", "imap");
    user_pref("mail.server.server_gmail2.hostname", "imap.gmail.com");
    user_pref("mail.server.server_gmail2.port", 993);
    user_pref("mail.server.server_gmail2.socketType", 3);
    user_pref("mail.server.server_gmail2.userName", "erik.frankling@gmail.com");
    user_pref("mail.server.server_gmail2.authMethod", 10);
    user_pref("mail.server.server_gmail2.is_gmail", true);
    user_pref("mail.server.server_gmail2.login_at_startup", true);
    user_pref("mail.smtpserver.smtp_gmail2.hostname", "smtp.gmail.com");
    user_pref("mail.smtpserver.smtp_gmail2.port", 587);
    user_pref("mail.smtpserver.smtp_gmail2.try_ssl", 2);
    user_pref("mail.smtpserver.smtp_gmail2.username", "erik.frankling@gmail.com");
    user_pref("mail.smtpserver.smtp_gmail2.authMethod", 10);

    // ===== KTH — erikfran@kth.se (plain password via sops) =====
    user_pref("mail.account.account_kth.identities", "id_kth");
    user_pref("mail.account.account_kth.server", "server_kth");
    user_pref("mail.identity.id_kth.fullName", "Erik Frankling");
    user_pref("mail.identity.id_kth.useremail", "erikfran@kth.se");
    user_pref("mail.identity.id_kth.valid", true);
    user_pref("mail.identity.id_kth.smtpServer", "smtp_kth");
    user_pref("mail.identity.id_kth.htmlSigText", "${sig}");
    user_pref("mail.identity.id_kth.sig_bottom", false);
    user_pref("mail.server.server_kth.type", "imap");
    user_pref("mail.server.server_kth.hostname", "webmail.kth.se");
    user_pref("mail.server.server_kth.port", 993);
    user_pref("mail.server.server_kth.socketType", 3);
    user_pref("mail.server.server_kth.userName", "ug.kth.se\\erikfran");
    user_pref("mail.server.server_kth.authMethod", 3);
    user_pref("mail.server.server_kth.login_at_startup", true);
    user_pref("mail.smtpserver.smtp_kth.hostname", "smtp.kth.se");
    user_pref("mail.smtpserver.smtp_kth.port", 587);
    user_pref("mail.smtpserver.smtp_kth.try_ssl", 2);
    user_pref("mail.smtpserver.smtp_kth.username", "ug.kth.se\\erikfran");
    user_pref("mail.smtpserver.smtp_kth.authMethod", 3);

    // ===== Outlook.com — erik.frankling@outlook.com (OAuth2) =====
    user_pref("mail.account.account_outlook.identities", "id_outlook");
    user_pref("mail.account.account_outlook.server", "server_outlook");
    user_pref("mail.identity.id_outlook.fullName", "Erik Frankling");
    user_pref("mail.identity.id_outlook.useremail", "erik.frankling@outlook.com");
    user_pref("mail.identity.id_outlook.valid", true);
    user_pref("mail.identity.id_outlook.smtpServer", "smtp_outlook");
    user_pref("mail.identity.id_outlook.htmlSigText", "${sig}");
    user_pref("mail.identity.id_outlook.sig_bottom", false);
    user_pref("mail.server.server_outlook.type", "imap");
    user_pref("mail.server.server_outlook.hostname", "outlook.office365.com");
    user_pref("mail.server.server_outlook.port", 993);
    user_pref("mail.server.server_outlook.socketType", 3);
    user_pref("mail.server.server_outlook.userName", "erik.frankling@outlook.com");
    user_pref("mail.server.server_outlook.authMethod", 10);
    user_pref("mail.server.server_outlook.login_at_startup", true);
    user_pref("mail.smtpserver.smtp_outlook.hostname", "smtp.office365.com");
    user_pref("mail.smtpserver.smtp_outlook.port", 587);
    user_pref("mail.smtpserver.smtp_outlook.try_ssl", 2);
    user_pref("mail.smtpserver.smtp_outlook.username", "erik.frankling@outlook.com");
    user_pref("mail.smtpserver.smtp_outlook.authMethod", 10);
  '';
}
