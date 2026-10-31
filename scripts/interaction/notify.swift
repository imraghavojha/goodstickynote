import Foundation
DistributedNotificationCenter.default().postNotificationName(Notification.Name(CommandLine.arguments[1]), object: CommandLine.arguments[2], userInfo: nil, deliverImmediately: true)
