import os

# Pocket ID as the only login method - no internal-auth fallback. If Pocket ID
# is ever down, recovery means editing this file (set back to
# ["oauth2", "internal"]) and restarting the container, not a UI fix.
AUTHENTICATION_SOURCES = ["oauth2"]
OAUTH2_AUTO_CREATE_USER = True

# No extra master-password prompt on top of Pocket ID's own passkey login. This
# only gates whether pgAdmin re-prompts before decrypting *saved* per-server
# passwords in this session (e.g. "Save Password" when connecting to the shared
# Home Server entry) - trade-off: if this container/its access is compromised,
# saved server passwords are easier to get at without also compromising a
# second secret.
MASTER_PASSWORD_REQUIRED = False

OAUTH2_CONFIG = [
    {
        "OAUTH2_NAME": "pocketid",
        "OAUTH2_DISPLAY_NAME": "Pocket ID",
        "OAUTH2_CLIENT_ID": os.environ["OAUTH2_CLIENT_ID"],
        "OAUTH2_CLIENT_SECRET": os.environ["OAUTH2_CLIENT_SECRET"],
        "OAUTH2_SERVER_METADATA_URL": "https://oidc.oskarrosen.io/.well-known/openid-configuration",
        "OAUTH2_SCOPE": "openid email profile",
        "OAUTH2_ICON": "fa-key",
        "OAUTH2_BUTTON_COLOR": "#4c6694",
        # PKCE on top of the confidential client secret - both are mandatory
        # together to turn PKCE on for a non-public pgAdmin OAuth2 client.
        "OAUTH2_CHALLENGE_METHOD": "S256",
        "OAUTH2_RESPONSE_TYPE": "code",
    }
]
