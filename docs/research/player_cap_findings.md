# BET player-cap findings

> **Historical research note.** This file preserves investigation details from development. It is not required for normal installation or use, and some hypotheses/keybinds may be superseded by the root README and changelog.


Generated from game root: `F:\Steam\steamapps\common\Backrooms_Escape_Together`

## Interpretation

The strongest evidence points to a cap implemented across the multiplayer settings UI and online session creation path, not a plain exposed config value.
The built-in Unreal cvar `net.MaxPlayersOverride` exists and reaches the game when launched through Steam, but it does not update the multiplayer settings UI cap.

## Runtime spawn diagnosis (2026-05-31, clean 7-player test — see CHANGELOG v2.4)

First genuine in-level capture (after fixing the CDO false-positive bug that made all prior "in-level" diagnostics actually run in the lobby). All 7 starters passed IrisGate cleanly; `K2_GetActorLocation` works in a real level.

Spawn mechanism (confirmed by player): **normal players spawn inside an ELEVATOR that descends as a cutscene** to the real spawn point.

DIAG evidence (host's view, 5 rounds 30s apart):
- 6 players read Z≈7486 in round 1 (mid-cutscene), then settle together at Z≈98.
- 1 player sits alone at Z≈-7902 every round — a dead-on match for a Neg1 (basement) bedroom PlayerStart (Z=-7900). That player was dropped at a Neg1 PlayerStart and **never rode the elevator**.

Key correction: the **runtime coordinate frame differs from the PlayerStart frame** (correct players are at Z≈98 at runtime, not their PlayerStart's Z=-8400 — a ~+8500 offset). Therefore the old absolute-Z threshold (-8150) is invalid; it mislabels every real player. **Detection must be RELATIVE cluster/outlier**, not an absolute floor constant. This conclusion was adversarially verified (high confidence, survived refutation).

8th player WUEWUE joined ~26s after travel into L_Startup → late-join spectator, never in-level (expected; not a bug).

Deferred issue: level→level transition requires all living players to return to the elevator, which likely cannot hold >6. Workaround: extra players die before transition. See CHANGELOG.

## Verified launch test

Using `launch\bet_modded_private_test.bat 12` now launches through Steam with AppId `2141730` and passes:

```text
-ExecCmds="net.MaxPlayersOverride 12"
```

Observed result:

- Steam/EOS initialization is healthy when launched through `steam.exe -applaunch 2141730`.
- The create-game UI still defaults to 4 players.
- The UI still clamps at 6 players.

Conclusion: `net.MaxPlayersOverride` may still affect lower-level `AGameSession` full-server checks, but it is not sufficient to raise the practical lobby cap. The next useful route is runtime discovery/hooking of the UI settings widget and session creation values.

## Hits

### `BET\Binaries\Win64\BETGameSteam-Win64-Shipping.exe`

- `DefaultMaxPlayers` `ascii` offset `172320456`
  - `a.t.e.P.o.i.n.t.S.t.a.c.k.S.e.t.t.i.n.g.s...................pyvF............@xEJ.....vEJ.....vEJ....PvEJ....................LobbyVisibilitySettingsRow......MaxPlayersSettingsRow...DefaultMaxPlayers.......MinSelectablePlayers....MaxSelectablePlayers....bDefaultPrivateLobby....DecreaseMaxPlayersButton........IncreaseMaxPlayersButton........PublicLobbyButton.......PrivateLobbyB`
- `MinSelectablePlayers` `ascii` offset `172320480`
  - `k.S.e.t.t.i.n.g.s...................pyvF............@xEJ.....vEJ.....vEJ....PvEJ....................LobbyVisibilitySettingsRow......MaxPlayersSettingsRow...DefaultMaxPlayers.......MinSelectablePlayers....MaxSelectablePlayers....bDefaultPrivateLobby....DecreaseMaxPlayersButton........IncreaseMaxPlayersButton........PublicLobbyButton.......PrivateLobbyButton......MaxPlayersValueT`
- `MaxSelectablePlayers` `ascii` offset `172320504`
  - `............pyvF............@xEJ.....vEJ.....vEJ....PvEJ....................LobbyVisibilitySettingsRow......MaxPlayersSettingsRow...DefaultMaxPlayers.......MinSelectablePlayers....MaxSelectablePlayers....bDefaultPrivateLobby....DecreaseMaxPlayersButton........IncreaseMaxPlayersButton........PublicLobbyButton.......PrivateLobbyButton......MaxPlayersValueText.....LobbyVisibilityV`
- `SelectedMaxPlayers` `ascii` offset `172320720`
  - `ateLobby....DecreaseMaxPlayersButton........IncreaseMaxPlayersButton........PublicLobbyButton.......PrivateLobbyButton......MaxPlayersValueText.....LobbyVisibilityValueText........SelectedMaxPlayers......bSelectedPrivateLobby...bHasInitializedState.....zvF....pyvF....@zEJ.....!.L............U.B.E.T.M.u.l.t.i.p.l.a.y.e.r.S.e.t.t.i.n.g.s.W.i.d.g.e.t........{EJ..................`
- `ClampMaxPlayers` `ascii` offset `172315712`
  - `ectiveActionType....E.O.b.j.e.c.t.i.v.e.G.r.a.n.t.T.y.p.e....eEJ.............fEJ............EObjectiveGrantType::PerPlayer..EObjectiveGrantType::AllPlayers.EObjectiveGrantType.....ClampMaxPlayers. zvF.....dEJ..... .L............`zvF.....eEJ..... .L............h..I........................E....................................'%J........................E......................`
- `IncreaseMaxPlayers` `ascii` offset `172316600`
  - `....GetLobbyVisibilityText...V.I........................E........................... iEJ.....V.I........................E...........................`iEJ....GetMaxPlayersText.......IncreaseMaxPlayers.......jEJ........................E....................................kEJ....................L...E...........................`/.A.....iEJ.....jEJ....E.P.C.G.P.o.i.n.t.S.t.a.c.k.A.`
- `IncreaseMaxPlayers` `ascii` offset `172320584`
  - `yVisibilitySettingsRow......MaxPlayersSettingsRow...DefaultMaxPlayers.......MinSelectablePlayers....MaxSelectablePlayers....bDefaultPrivateLobby....DecreaseMaxPlayersButton........IncreaseMaxPlayersButton........PublicLobbyButton.......PrivateLobbyButton......MaxPlayersValueText.....LobbyVisibilityValueText........SelectedMaxPlayers......bSelectedPrivateLobby...bHasInitialize`
- `IncreaseMaxPlayers` `ascii` offset `174310948`
  - `i.t.y.V.a.l.u.e.T.e.x.t.........M.P.-...M.P.+...P.L.-...P.L.+...P.r.i.v.a.t.e.L.o.b.b.y.T.e.x.t.........P.u.b.l.i.c.L.o.b.b.y.T.e.x.t...&ThisClass::DecreaseMaxPlayers..&ThisClass::IncreaseMaxPlayers..&ThisClass::TogglePrivateLobby..0.0.0.0.........L.o.a.d.i.n.g.L.e.v.e.l.N.a.m.e.........&ThisClass::HandleNextButtonClicked.....&ThisClass::HandleBackButtonClicked.......cJ......`
- `DecreaseMaxPlayers` `ascii` offset `172316096`
  - `.....'%J........................E...................................HZEJ....................L...E..............................C.....fEJ.....fEJ.....gEJ....PgEJ....`.HF.....1sF....DecreaseMaxPlayers...............wvF.............gEJ.....gEJ.............gEJ.....................V.I........................E...........................0..C.... hEJ.....zvF.....wvF.....hEJ..... .L..`
- `DecreaseMaxPlayers` `ascii` offset `172320552`
  - `....PvEJ....................LobbyVisibilitySettingsRow......MaxPlayersSettingsRow...DefaultMaxPlayers.......MinSelectablePlayers....MaxSelectablePlayers....bDefaultPrivateLobby....DecreaseMaxPlayersButton........IncreaseMaxPlayersButton........PublicLobbyButton.......PrivateLobbyButton......MaxPlayersValueText.....LobbyVisibilityValueText........SelectedMaxPlayers......bSelec`
- `DecreaseMaxPlayers` `ascii` offset `174310916`
  - `e.x.t...L.o.b.b.y.V.i.s.i.b.i.l.i.t.y.V.a.l.u.e.T.e.x.t.........M.P.-...M.P.+...P.L.-...P.L.+...P.r.i.v.a.t.e.L.o.b.b.y.T.e.x.t.........P.u.b.l.i.c.L.o.b.b.y.T.e.x.t...&ThisClass::DecreaseMaxPlayers..&ThisClass::IncreaseMaxPlayers..&ThisClass::TogglePrivateLobby..0.0.0.0.........L.o.a.d.i.n.g.L.e.v.e.l.N.a.m.e.........&ThisClass::HandleNextButtonClicked.....&ThisClass::Handle`
- `GetMaxPlayersText` `ascii` offset `172316576`
  - `.....................hEJ....GetLobbyVisibilityText...V.I........................E........................... iEJ.....V.I........................E...........................`iEJ....GetMaxPlayersText.......IncreaseMaxPlayers.......jEJ........................E....................................kEJ....................L...E...........................`/.A.....iEJ.....jEJ....E.P.C`
- `MaxPlayersValueText` `ascii` offset `172320664`
  - `electablePlayers....MaxSelectablePlayers....bDefaultPrivateLobby....DecreaseMaxPlayersButton........IncreaseMaxPlayersButton........PublicLobbyButton.......PrivateLobbyButton......MaxPlayersValueText.....LobbyVisibilityValueText........SelectedMaxPlayers......bSelectedPrivateLobby...bHasInitializedState.....zvF....pyvF....@zEJ.....!.L............U.B.E.T.M.u.l.t.i.p.l.a.y.e.r.S`
- `MaxPlayersValueText` `utf16le` offset `174310704`
  - `....P3.F.....3.F.....4.F.......B.......A.......A....p..A.......B.......B....@..B....p..A.....2.F.....2.F....p2.F.....3.F.....3.F....W._.C.o.n.n.e.c.t.i.n.g.S.c.r.e.e.n._.C.........M.a.x.P.l.a.y.e.r.s.V.a.l.u.e.T.e.x.t...L.o.b.b.y.V.i.s.i.b.i.l.i.t.y.V.a.l.u.e.T.e.x.t.........M.P.-...M.P.+...P.L.-...P.L.+...P.r.i.v.a.t.e.L.o.b.b.y.T.e.x.t.........P.u.b.l.i.c.L.o.b.b.y.T.e.x.t...&ThisClass::Decrea`
- `UBETMultiplayerSettingsWidget` `utf16le` offset `172320832`
  - `Button......MaxPlayersValueText.....LobbyVisibilityValueText........SelectedMaxPlayers......bSelectedPrivateLobby...bHasInitializedState.....zvF....pyvF....@zEJ.....!.L............U.B.E.T.M.u.l.t.i.p.l.a.y.e.r.S.e.t.t.i.n.g.s.W.i.d.g.e.t........{EJ........................E............................|EJ........................E............................|EJ........................E............................C.A..`
- `CreateGameBaseWidget.cpp` `ascii` offset `174311407`
  - `.r. .J.o.u.r.n.e.y.=.%.s. .C.u.r.r.e.n.t.B.e.f.o.r.e.=.%.s. .P.e.n.d.i.n.g.O.v.e.r.r.i.d.e.=.%.s.....C:\BuildAgent\work\513ea6508d221a7d\Source\BETGame\Private\UI\Lobby\CreateGame\CreateGameBaseWidget.cpp. .cJ......cJ............[.J.o.u.r.n.e.y. .o.v.e.r.r.i.d.e.]. .S.i.n.g.l.e.P.l.a.y.e.r. .J.o.u.r.n.e.y.=.%.s. .C.u.r.r.e.n.t.A.f.t.e.r.=.%.s.....Pk.F....0k.F....pO.A....&ThisClass:`
- `Session.MaxPlayers` `ascii` offset `174024904`
  - `.PCGGenerated.......GameplayCue.Equipment.PartyHat..Auth.State.Inactive.....Auth.State.LoggingIn....Auth.State.LoggedIn.....Auth.State.ReauthRequired.......Auth.State.AuthFailed...Session.MaxPlayers......VoiceChannel....VoiceChannel.Alive......VoiceChannel.Dead.......Interaction.FocusedChanged......Interaction.ItemPickedUp........Interactable.LightSwitch.StateChange....Intera`
- `EOS_SessionModification_SetMaxPlayers` `ascii` offset `193199886`
  - `ns_RemoveNotifyLeaveSessionRequested..@.EOS_SessionModification_SetHostAddress..D.EOS_SessionModification_SetPermissionLevel..B.EOS_SessionModification_SetJoinInProgressAllowed..C.EOS_SessionModification_SetMaxPlayers.A.EOS_SessionModification_SetInvitesAllowed.;.EOS_SessionModification_AddAttribute..5.EOS_SessionDetails_CopyInfo.8.EOS_SessionDetails_GetSessionAttributeCount.6.EOS_SessionDetail`
- `EOS_SessionModification_SetMaxPlayers` `utf16le` offset `166523056`
  - `i.f.i.c.a.t.i.o.n._.S.e.t.P.e.r.m.i.s.s.i.o.n.L.e.v.e.l.(.). .f.a.i.l.e.d. .w.i.t.h. .E.O.S. .r.e.s.u.l.t. .c.o.d.e. .(.%.s.)..........H.......I....D..........H.......I....I.......E.O.S._.S.e.s.s.i.o.n.M.o.d.i.f.i.c.a.t.i.o.n._.S.e.t.M.a.x.P.l.a.y.e.r.s.(.). .s.e.t. .t.o. .(.%.d.). .f.o.r. .s.e.s.s.i.o.n. .(.%.s.).........E.O.S._.S.e.s.s.i.o.n.M.o.d.i.f.i.c.a.t.i.o.n._.S.e.t.M.a.x.P.l.a.y.e.r.s.(.). .f.a.i.l.e.d. .w.i.t.h. .E.O.S.`
- `EOS_SessionModification_SetMaxPlayers` `utf16le` offset `166523200`
  - `....D..........H.......I....I.......E.O.S._.S.e.s.s.i.o.n.M.o.d.i.f.i.c.a.t.i.o.n._.S.e.t.M.a.x.P.l.a.y.e.r.s.(.). .s.e.t. .t.o. .(.%.d.). .f.o.r. .s.e.s.s.i.o.n. .(.%.s.).........E.O.S._.S.e.s.s.i.o.n.M.o.d.i.f.i.c.a.t.i.o.n._.S.e.t.M.a.x.P.l.a.y.e.r.s.(.). .f.a.i.l.e.d. .w.i.t.h. .E.O.S. .r.e.s.u.l.t. .c.o.d.e. .(.%.s.)............H.......I....T..........H.......I....Y...............E.O.S._.S.e.s.s.i.o.n.M.o.d.i.f.i.c.a.t.i.o.n.`
- `NumPublicConnections` `ascii` offset `166524520`
  - `a.t.i.o.n._.A.d.d.A.t.t.r.i.b.u.t.e.(.). .f.a.i.l.e.d. .f.o.r. .a.t.t.r.i.b.u.t.e. .n.a.m.e. .(.%.s.). .w.i.t.h. .E.O.S. .r.e.s.u.l.t. .c.o.d.e. .(.%.s.)...NumPrivateConnections...NumPublicConnections....bAntiCheatProtected.....bUsesStats......bIsDedicated....BuildUniqueId......H.......I...............H.......I....................E.O.S._.M.e.t.r.i.c.s._.B.e.g.i.n.P.l.a.y.e.r.S.`
- `NumPublicConnections` `utf16le` offset `164472642`
  - `.....H.......I....?..........H.......I....@..........H.......I....A..........H.......I....B..........H.......I....G.......d.u.m.p.i.n.g. .S.e.s.s.i.o.n.S.e.t.t.i.n.g.s.:. .........N.u.m.P.u.b.l.i.c.C.o.n.n.e.c.t.i.o.n.s.:. .%.d.........N.u.m.P.r.i.v.a.t.e.C.o.n.n.e.c.t.i.o.n.s.:. .%.d.......b.I.s.L.a.n.M.a.t.c.h.:. .%.s...........b.I.s.D.e.d.i.c.a.t.e.d.:. .%.s.........b.U.s.e.s.S.t.a.t.s.:. .%.s.`
- `NumPublicConnections` `utf16le` offset `166529616`
  - `t. .c.o.d.e. .(.%.s.)..........H.......I....R.......E.O.S._.L.o.b.b.y.S.e.a.r.c.h._.S.e.t.P.a.r.a.m.e.t.e.r.(.). .f.a.i.l.e.d. .w.i.t.h. .E.O.S. .r.e.s.u.l.t. .c.o.d.e. .(.%.s.)...N.u.m.P.u.b.l.i.c.C.o.n.n.e.c.t.i.o.n.s.........N.u.m.P.r.i.v.a.t.e.C.o.n.n.e.c.t.i.o.n.s.......b.A.n.t.i.C.h.e.a.t.P.r.o.t.e.c.t.e.d...b.U.s.e.s.S.t.a.t.s.....b.I.s.D.e.d.i.c.a.t.e.d.........B.u.i.l.d.U.n.i.q.u.e.I.d...`
- `PublicConnections` `ascii` offset `164504592`
  - `....06.I....................L...E....................... ...0..C.....V.I........................E............................A.D....`4.I.....4.I.....4.I.... 5.I....`5.I.....5.I....PublicConnections.......bUseLAN.bUseLobbiesIfAvailable..CreateSession.............WI........................E..............................A......6I........................E........................`
- `PublicConnections` `ascii` offset `166524523`
  - `.i.o.n._.A.d.d.A.t.t.r.i.b.u.t.e.(.). .f.a.i.l.e.d. .f.o.r. .a.t.t.r.i.b.u.t.e. .n.a.m.e. .(.%.s.). .w.i.t.h. .E.O.S. .r.e.s.u.l.t. .c.o.d.e. .(.%.s.)...NumPrivateConnections...NumPublicConnections....bAntiCheatProtected.....bUsesStats......bIsDedicated....BuildUniqueId......H.......I...............H.......I....................E.O.S._.M.e.t.r.i.c.s._.B.e.g.i.n.P.l.a.y.e.r.S.`
- `PublicConnections` `ascii` offset `171028614`
  - `tIntSetting.....OF..............1J......1J......1J....`.1J............2.......OnInitializationComplete.........V.I........................E...........................@.1J....GetMaxPublicConnections..V.I........................E...........................@..H........................E.....................................1J..............1J........................E..............`
- `PublicConnections` `ascii` offset `171029290`
  - `....1J......1J.... .1J....GetNumOpenPrivateConnections....Privilege.......GetCachedPrivilegeResult.........V.I........................E.............................1J....GetNumOpenPublicConnections......V.I........................E...........................@.1J.....V.I........................E.............................1J....@..H........................E..................`
- `PublicConnections` `ascii` offset `172434995`
  - `..7GJ....H7GJ....ServerSpawnItem.B.E.T.J.o.i.n.a.b.l.e.L.o.b.b.y.E.n.t.r.y.......B.E.T.S.t.a.t.e.T.r.e.e.C.o.n.d.i.t.i.o.n._.A.c.t.o.r.H.a.s.A.b.i.l.i.t.y.S.y.s.t.e.m.T.a.g.....MaxPublicConnections....BETStateTreeCondition_ActorHasAbilitySystemTag..NumOpenPublicConnections........PingInMs.........FwF....@GwF.....7GJ....P,.L............SearchResultIndex.......SessionSubsystem`
- `PublicConnections` `ascii` offset `172435071`
  - `.....B.E.T.S.t.a.t.e.T.r.e.e.C.o.n.d.i.t.i.o.n._.A.c.t.o.r.H.a.s.A.b.i.l.i.t.y.S.y.s.t.e.m.T.a.g.....MaxPublicConnections....BETStateTreeCondition_ActorHasAbilitySystemTag..NumOpenPublicConnections........PingInMs.........FwF....@GwF.....7GJ....P,.L............SearchResultIndex.......SessionSubsystemName....S.e.r.v.e.r.S.p.a.w.n.P.l.a.y.e.r.C.l.o.n.e.....BETJoinableLobbyEntr`
- `PublicConnections` `utf16le` offset `164472112`
  - `n.:. .........O.w.n.i.n.g.P.l.a.y.e.r.N.a.m.e.:. .%.s.........O.w.n.i.n.g.P.l.a.y.e.r.I.d.:. .%.s.....N.u.m.O.p.e.n.P.r.i.v.a.t.e.C.o.n.n.e.c.t.i.o.n.s.:. .%.d.......N.u.m.O.p.e.n.P.u.b.l.i.c.C.o.n.n.e.c.t.i.o.n.s.:. .%.d.........S.e.s.s.i.o.n.I.n.f.o.:. .%.s............H.......I....4..........H.......I....5..........H.......I....6..........H.......I....7..........H.......I....8..........H..`
- `PublicConnections` `utf16le` offset `164472648`
  - `.......I....?..........H.......I....@..........H.......I....A..........H.......I....B..........H.......I....G.......d.u.m.p.i.n.g. .S.e.s.s.i.o.n.S.e.t.t.i.n.g.s.:. .........N.u.m.P.u.b.l.i.c.C.o.n.n.e.c.t.i.o.n.s.:. .%.d.........N.u.m.P.r.i.v.a.t.e.C.o.n.n.e.c.t.i.o.n.s.:. .%.d.......b.I.s.L.a.n.M.a.t.c.h.:. .%.s...........b.I.s.D.e.d.i.c.a.t.e.d.:. .%.s.........b.U.s.e.s.S.t.a.t.s.:. .%.s.`
- `PublicConnections` `utf16le` offset `166529622`
  - `o.d.e. .(.%.s.)..........H.......I....R.......E.O.S._.L.o.b.b.y.S.e.a.r.c.h._.S.e.t.P.a.r.a.m.e.t.e.r.(.). .f.a.i.l.e.d. .w.i.t.h. .E.O.S. .r.e.s.u.l.t. .c.o.d.e. .(.%.s.)...N.u.m.P.u.b.l.i.c.C.o.n.n.e.c.t.i.o.n.s.........N.u.m.P.r.i.v.a.t.e.C.o.n.n.e.c.t.i.o.n.s.......b.A.n.t.i.C.h.e.a.t.P.r.o.t.e.c.t.e.d...b.U.s.e.s.S.t.a.t.s.....b.I.s.D.e.d.i.c.a.t.e.d.........B.u.i.l.d.U.n.i.q.u.e.I.d...`
- `MaxPublicConnections` `ascii` offset `171028611`
  - `.GetIntSetting.....OF..............1J......1J......1J....`.1J............2.......OnInitializationComplete.........V.I........................E...........................@.1J....GetMaxPublicConnections..V.I........................E...........................@..H........................E.....................................1J..............1J........................E..............`
- `MaxPublicConnections` `ascii` offset `172434992`
  - `.....7GJ....H7GJ....ServerSpawnItem.B.E.T.J.o.i.n.a.b.l.e.L.o.b.b.y.E.n.t.r.y.......B.E.T.S.t.a.t.e.T.r.e.e.C.o.n.d.i.t.i.o.n._.A.c.t.o.r.H.a.s.A.b.i.l.i.t.y.S.y.s.t.e.m.T.a.g.....MaxPublicConnections....BETStateTreeCondition_ActorHasAbilitySystemTag..NumOpenPublicConnections........PingInMs.........FwF....@GwF.....7GJ....P,.L............SearchResultIndex.......SessionSubsystem`
- `CreateSession` `ascii` offset `164504648`
  - ` ...0..C.....V.I........................E............................A.D....`4.I.....4.I.....4.I.... 5.I....`5.I.....5.I....PublicConnections.......bUseLAN.bUseLobbiesIfAvailable..CreateSession.............WI........................E..............................A......6I........................E...........................P..D....@9.I........................E............`
- `CreateSession` `ascii` offset `166649917`
  - `..I....................C:\UnrealEngine\Engine\Plugins\Online\OnlineSubsystemSteam\Source\Private\OnlineSessionInterfaceSteam.cpp..........H.......I....$.......FOnlineSessionSteam::CreateSession......[.%.h.s.]. .T.h.e. .v.a.l.u.e.s. .o.f. .F.O.n.l.i.n.e.S.e.s.s.i.o.n.S.e.t.t.i.n.g.s.:.:.b.U.s.e.s.P.r.e.s.e.n.c.e. .a.n.d. .F.O.n.l.i.n.e.S.e.s.s.i.o.n.S.e.t.t.i.n.g.s.:.:.b.`
- `CreateSession` `ascii` offset `171033951`
  - `J....@.1J....CommonUserOnInitializeCompleteMulticast__DelegateSignature.................I........................E...........................P.OF......1J............CommonSessionOnCreateSessionComplete_Dynamic__DelegateSignature.8.1J........................E.............................OF.....k6I....................L...E.......................(......A.....f.H............`
- `CreateSession` `ascii` offset `171040293`
  - `.1J....x.1J......1J......1J............r........V.I........................E...........................K2_OnUserRequestedSessionEvent....1J....K2_OnJoinSessionCompleteEvent...K2_OnCreateSessionCompleteEvent.K2_OnSessionInformationChangedEvent.....K2_OnDestroySessionRequestedEvent.......bUseLobbiesDefault......GetNumLocalPlayers......bUseLobbiesVoiceChatDefault.....bUseBe`
- `CreateSession` `ascii` offset `171924848`
  - `t.a.r.t. .a. .s.e.s.s.i.o.n............H.....o?J....................C:\BuildAgent\work\513ea6508d221a7d\Plugins\OnlineSubSystemUtilities\Source\OnlineSubSystemUtilities\Private\EIKCreateSessionCallbackProxyAdvanced.cpp.....H.....o?J............S.e.s.s.i.o.n. .c.r.e.a.t.i.o.n. .c.o.m.p.l.e.t.e.d... .A.u.t.o.m.a.t.i.c. .s.t.a.r.t. .i.s. .t.u.r.n.e.d. .o.n.,. .s.t.a.r.t.i.n`
- `CreateSession` `ascii` offset `193199035`
  - `_Sanctions_QueryActivePlayerSanctions..1.EOS_Sanctions_GetPlayerSanctionCount../.EOS_Sanctions_CopyPlayerSanctionByIndex.0.EOS_Sanctions_CreatePlayerSanctionAppeal..X.EOS_Sessions_CreateSessionModification..n.EOS_Sessions_UpdateSessionModification..m.EOS_Sessions_UpdateSession..Z.EOS_Sessions_DestroySession.`.EOS_Sessions_JoinSession..k.EOS_Sessions_StartSession.\.EOS_Se`
- `CreateSession` `utf16le` offset `164505850`
  - `...C.A.....F.D....PH.D.....A.D.....:.I....`.%L............X..I....................R...E............................F.D....X..I..................$.....E...........................U.C.r.e.a.t.e.S.e.s.s.i.o.n.C.a.l.l.b.a.c.k.P.r.o.x.y....9.I.....:.I.....:.I.....:.I.......D.....l.D......................... ...H.D.....H.D.... I.D......................WI........................E...........`
- `CreateSession` `utf16le` offset `164539488`
  - `....`..A....`..A.... ..A....0..A.......A....p1.A....p..A....`..A....@..A....`..A....`..A....p`.A.......D....@.\D......\D....P.\D.......D.......D.... ..D.......D....`..A.....x.D....C.r.e.a.t.e.S.e.s.s.i.o.n.C.a.l.l.b.a.c.k.P.r.o.x.y.....H6.I....P,.D....C.r.e.a.t.e.S.e.s.s.i.o.n...............S.e.s.s.i.o.n.s. .n.o.t. .s.u.p.p.o.r.t.e.d. .b.y. .O.n.l.i.n.e. .S.u.b.s.y.s.t.e.m.....C.r.e.`
- `CreateSession` `utf16le` offset `164539560`
  - `....`..A....`..A....p`.A.......D....@.\D......\D....P.\D.......D.......D.... ..D.......D....`..A.....x.D....C.r.e.a.t.e.S.e.s.s.i.o.n.C.a.l.l.b.a.c.k.P.r.o.x.y.....H6.I....P,.D....C.r.e.a.t.e.S.e.s.s.i.o.n...............S.e.s.s.i.o.n.s. .n.o.t. .s.u.p.p.o.r.t.e.d. .b.y. .O.n.l.i.n.e. .S.u.b.s.y.s.t.e.m.....C.r.e.a.t.e.S.e.s.s.i.o.n.C.a.l.l.b.a.c.k.......S.t.a.r.t.S.e.s.s.i.o.n.C.a.l.`
- `CreateSession` `utf16le` offset `164539688`
  - `i.o.n.C.a.l.l.b.a.c.k.P.r.o.x.y.....H6.I....P,.D....C.r.e.a.t.e.S.e.s.s.i.o.n...............S.e.s.s.i.o.n.s. .n.o.t. .s.u.p.p.o.r.t.e.d. .b.y. .O.n.l.i.n.e. .S.u.b.s.y.s.t.e.m.....C.r.e.a.t.e.S.e.s.s.i.o.n.C.a.l.l.b.a.c.k.......S.t.a.r.t.S.e.s.s.i.o.n.C.a.l.l.b.a.c.k............D....`..A.......A....`g.A.......A....`P.A.....v.A....`..A....0..A....0&.A.....F.A....`..A....`..A....`..A..`
- `CreateSession` `utf16le` offset `166525794`
  - `l.y. .w.i.l.l. .b.e. .a.u.t.o.m.a.t.i.c.a.l.l.y. .s.e.t. .t.o. .f.a.l.s.e. .a.s. .w.e.l.l.........FOnlineSessionEOS::CreateEOSSession.............%.h.s. .E.O.S._.S.e.s.s.i.o.n.s._.C.r.e.a.t.e.S.e.s.s.i.o.n.M.o.d.i.f.i.c.a.t.i.o.n. .f.a.i.l.e.d. .R.e.s.u.l.t.=.%.s...U.s.e.L.o.c.a.l.I.P.s...%.h.s. .E.O.S._.S.e.s.s.i.o.n.M.o.d.i.f.i.c.a.t.i.o.n._.S.e.t.H.o.s.t.A.d.d.r.e.s.s.(.%.s.). .r.`
- `CreateSession` `utf16le` offset `166531210`
  - `r.e.s.u.l.t.s.............E.O.S._.S.e.s.s.i.o.n.S.e.a.r.c.h._.F.i.n.d.(.). .f.a.i.l.e.d. .w.i.t.h. .E.O.S. .r.e.s.u.l.t. .c.o.d.e. .(.%.s.)...............E.O.S._.S.e.s.s.i.o.n.s._.C.r.e.a.t.e.S.e.s.s.i.o.n.S.e.a.r.c.h.(.). .f.a.i.l.e.d. .w.i.t.h. .E.O.S. .r.e.s.u.l.t. .c.o.d.e. .(.%.s.)...bucket..D.E.D.I.C.A.T.E.D.O.N.L.Y.......M.A.P.N.A.M.E...E.M.P.T.Y.O.N.L.Y.......S.E.C.U.R.E.O.N.`
- `TryGetActiveSessionPopulation` `ascii` offset `172431952`
  - `........................E............................V.I....................L...E..............................A....`+GJ.....+GJ.....+GJ....OutCurrentPlayers.......OutMaxPlayers...TryGetActiveSessionPopulation....-GJ........................E....................................V.I....................L...E............................u.A....p,GJ.....,GJ....OutLobbyCode....TryGetAuthoritati`
- `TryGetSessionIntSetting` `ascii` offset `172432376`
  - `........E............................`.I........................E............................V.I....................L...E............................u.A....0-GJ....h-GJ.....-GJ....TryGetSessionIntSetting..1GJ........................E.....................0.....@?wF.....1GJ........................E.....................@.....p?wF....01GJ........................E.....................P`
- `net.MaxPlayersOverride` `utf16le` offset `161556536`
  - `c.o.u.n.t... .U.s.e.f.u.l. .f.o.r. .t.e.s.t.i.n.g. .f.u.l.l. .s.e.r.v.e.r.s..................4.I....05.I....p5.I.....5.I.....5.I....06.I.....6.I....07.I.....7.I....P8.I.....8.I....n.e.t...M.a.x.P.l.a.y.e.r.s.O.v.e.r.r.i.d.e.............x;.I....................L...E.......................8...@..B......gI....................L...E.......................8...@.'B.....V.I........................E...........`
- `Server full` `utf16le` offset `161591424`
  - `e.r.v.e.r.!............I....p..I....................A.p.p.r.o.v.e.L.o.g.i.n.:. .A. .m.a.x.i.m.u.m. .o.f. .%.i. .s.p.l.i.t.s.c.r.e.e.n. .p.l.a.y.e.r.s. .a.r.e. .a.l.l.o.w.e.d.......S.e.r.v.e.r. .f.u.l.l...........S.p.l.i.t.s.c.r.e.e.n.C.o.u.n.t.........M.a.x.i.m.u.m. .s.p.l.i.t.s.c.r.e.e.n. .p.l.a.y.e.r.s... ..I....p..I....................A.G.a.m.e.S.e.s.s.i.o.n.:.:.G.e.t.N.e.x.t.`

### `BET\Content\Paks\BET-Windows.utoc`

- `BP_LobbyGameMode` `ascii` offset `24262536`
  - `fWall_26.ubulk.'...M_Relaxed_Walk_Turn_180_R_Rfoot.uasset. ...T_Cabbage_tgrmacdpa_4K_N.uasset.%...W_UndergroundAmbienceCrossFade.ubulk.%...T_OldBrickWall_wmgjddk_8K_ORDp.ubulk.....BP_LobbyGameMode.uasset.....SM_Fuse_LowPoly.ubulk. ...BP_ElectricalCeilingWire.uasset.....subst_Netting_Normal.uasset.D...MI_Scratched_Polyvinylpyrrolidone_Plastic_schcbgfp_4K_Whiite.uasset.0...M_`
- `BP_LobbyPlayerController` `ascii` offset `24461879`
  - `..S_Trigger.uasset.....T_Door_2_AO.uasset.....T_Graffiti_WideHapp.uasset.!...m_med_nrw_thumb_02_r_pose.uasset.....W_LightSwitchFlick_Cue.uasset.....SM_Blockout_Sphere_Q4.ubulk. ...BP_LobbyPlayerController.uasset.$...M_Neutral_Walk_Stop_FL_Rfoot.uasset. ...MI_FunGraffitiPacked_1_r.uasset.%...M_Neutral_Run_Pivot_F_B_Rfoot.uasset.....Hand_N_G.ubulk./...MI_Modular_Concrete_Median_vcdmd`
- `WBP_MultiplayerSettings` `ascii` offset `24191604`
  - `Filter_by_Cem_TEZCAN_Random_offset_map.uasset.....TX_Rack_D_01_NRM.uasset.....SM_Chocolate_Milk.ubulk.(...wild-roar-monster-SBA-300062739_1.ubulk.....T_Grunge_Dirt_Thin.uasset.#...WBP_MultiplayerSettingsInfo.uasset.....Cans_Paint_B_BaseColor.uasset.1...Foley_fs_1p_sneaker_concrete_scuffPivot_05.ubulk.#...M_Neutral_Walk_Stop_B_Lfoot.uasset.....PCG_Level_FUN.uasset.....SM_fuse_box_A`
- `WBP_MultiplayerSettings` `ascii` offset `24269447`
  - `tor_ARM_01.ubulk.....Cone.uasset.....MI_IndustrialNumber_1.uasset.2...T_Modular_Floor_Molding_Kit_wfsndg2dw_8K_N.uasset.....MS_MetalScrape.uasset.....PSD_SM_Mover_Spins.uasset.$...WBP_MultiplayerSettingsPanel.uasset.....MF_RefractionDirection.uasset.....TX_Sign_Set_NN_10a_RMA.ubulk.....T_Electrical_N.ubulk.....Speaker_Scream_Man_1.ubulk.....Vest_Masks.ubulk.....Win_Key_Dark.uasset`
- `WBP_MultiplayerSettings` `ascii` offset `24432604`
  - `4mx350cm_Brick_D.ubulk.....Santa_Hat_PomPom.uasset.....SampleContent.....MeshSockets.....Elements.....MeshSocketsToPoints.uasset.+...T_Rusted_Painted_Metal_tebjbjan_8K_D.ubulk.)...WBP_MultiplayerSettings_LobbyCode.uasset.S...437732-Sony_DVD_VCR_Player-SLD560P-Button-Press-VHS_Eject-ST-D100_44100_1_7.uasset.....Adrenaline.....GE_Adrenaline.uasset.!...TV_black_parts_Base_Color.uasse`
- `WBP_MultiplayerLobbyView` `ascii` offset `24310190`
  - `_Tr1_48000_1_11.ubulk.,...T_Rusty_Bulkhead_Light_vgyidfpaw_8K_N.ubulk.....Volume.uasset.,...Foley_fs_1p_sneaker_concrete_walk_17.uasset.$...BP_Level3_RepairableWallWire.uasset. ...WBP_MultiplayerLobbyView.uasset.!...SheetMetal001_2K_NormalGL.uasset.....SM_MetalWire_350cm.ubulk.....M_Head_Baked.uasset. ...BP_MilkCarton_Definition.uasset.-...TX_KitchenCabinets_Trims_Synthetic_ORM.ubu`
