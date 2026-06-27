@echo off
chcp 65001 >nul
rem Fisherman's Horizon をプレイ実行する
set "GODOT=C:\Users\aoe10\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe"
start "" "%GODOT%" --path "%~dp0"
