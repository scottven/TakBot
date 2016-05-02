# TakBot

TakBot is a script that connects various implementations of Tak playing AIs to the playtak.com server.

## User Interface

TakBot interacts with users through the playtak.com chat system.  TakBot will respond to the following commands:

### TakBot: help

TakBot will reply with a link to this document.

### TakBot: play

TakBot will look for a game that you created and attempt to join it.  You must create the game using playtak's "New Game" button first.

If you want to play against a specific AI, you can provide the AI name after "play".  For example "TakBot: play rtak".  To get the list of AI names, see the list command below.

###TakBot: list

TakBot will reply in the chat with a list of the AIs that it can use.

###TakBot: ai

If you are currently playing a game and want to change to a different AI, use this command and give the AI name.  For example "TakBot: ai rtak".

## Undo

TakBot will accept any requests to undo a move.  It also assumes that any time a user asks it to undo one of its moves, that's because the user actually wants to take back their previous move.  In such a case, it will immediately issue an undo request after accepting the user's.  If TakBot gets and undo request while it is still thinking about its next move, it will accept that request and abandon the current thinking.

## Draw

TakBot will always accept any offers to draw.

##Administrative Details

TakBot also responds to a few commands only from the configured owner username.

###TakBot: reboot

TakBot will re-exec itself to pick up and code changes.  If run in fork mode, this will not impact any currently in-progress games.

###TakBot: fight

The owner can tell TakBot to join a game offered by a different player.  This can be used to have TakBot play another bot or a player who's having a hard time getting TakBot to join their game.

###TakBot: talk

This allows TakBot to make some side-comments about the AI engines and games it played.

###TakBot: no talk

Tells TakBot to stop making those side-comments.

###TakBot: debug
###TakBot: no debug

Tells TakBot to start and stop logging debug messages of the specified type.  The types currently supported are ai, rtak, torch, ptn, wire, undo.  For example "TakBot: no debug wire".

##AI Connections

TakBot currently supports two styles of AI connections.

###Web Service AI

TakBot can sends requests to any AI that implements the web service API described in https://docs.google.com/document/d/1E_vtbNJ2hkHEYP_rfm-oFkz1wmq47JvxfDFG7Fo75Qo/edit?usp=sharing

###Torch

TakBot can also interact with a Torch based AI using the following convention.

1. TakBot launches 'th' with the Lua script as the argument.
2. TakBot sends the PTN for the game into th on STDIN and then closes STDIN.
3. TakBot reads out the move from STDOUT.  The move should be on the last line of text output (second to last line of STDOUT since th will print the return value after).  It should have the keyword "move: " followed by a PTN notated move.
4. The th process should then exit.

