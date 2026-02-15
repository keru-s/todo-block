//
//  SidebarDestination.swift
//  todo block
//
//  Created by Codex on 2026/2/16.
//

import Foundation

enum SidebarDestination: Hashable {
    case month(year: Int, month: Int)
    case longTerm
}
