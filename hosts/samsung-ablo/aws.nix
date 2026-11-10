{ ... }:
let
  developer = {
    sso_session = "ablo";
    sso_account_id = "867344471746";
    sso_role_name = "AbloDeveloper";
    region = "eu-north-1";
    output = "json";
  };
in
{
  # All user-run harnesses share the AWS CLI's native SSO cache. No copied
  # access keys or harness-specific credential wrapper is needed.
  programs.awscli.settings = {
    default = developer;
    "profile erik" = developer;
    "profile ablo" = developer;
    "profile ablo-readonly" = developer // {
      sso_role_name = "AbloReadOnly";
    };
  };
}
