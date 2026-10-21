{ DN_NET: the network panels (docs/NETWORK.md) are in this build. They run their programs through Process and Pipes,
  which the DOS target has not; the mini build leaves them out. The units of the network test DN_NET, not the target. }
{$IF NOT (DEFINED(GO32V2) OR DEFINED(DN_MINI))}
  {$DEFINE DN_NET}
{$ENDIF}
