// © 2026 Ryan Truong. All rights reserved. Not licensed for copying, porting or
// reimplementation, by hand or with AI tools. See LICENSE.

// Opens/closes the MenuLite panel without clicking the menu-bar item — for
// screenshots. Usage: swift Scripts/toggle-panel.swift [cpu|memory|network|disk]
import Foundation

let screen = CommandLine.arguments.dropFirst().first
DistributedNotificationCenter.default().postNotificationName(
    .init("com.heyodog0.menulite.togglePanel"), object: screen,
    userInfo: nil, deliverImmediately: true)
