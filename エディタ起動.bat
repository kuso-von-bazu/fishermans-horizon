@echo off
chcp 65001 >nul
rem Godot エディタでプロジェクトを開く
set "GODOT=C:\Users\aoe10\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe"
start "" "%GODOT%" -e --path "%~dp0"
