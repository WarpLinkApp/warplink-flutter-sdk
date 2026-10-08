import Foundation
import UIKit

/// Pulls link URLs out of the objects UIKit hands to the delegates.
enum IncomingUrlExtractor {
    /// Key of the user activity inside the launch options' activity dictionary.
    private static let activityKey = "UIApplicationLaunchOptionsUserActivityKey"

    /// The URL of a web browsing activity (a Universal Link), else `nil`.
    static func url(from activity: NSUserActivity) -> URL? {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb else { return nil }
        return activity.webpageURL
    }

    /// The launch URLs in `didFinishLaunchingWithOptions`: the activity first,
    /// then a plain URL.
    static func urls(fromLaunchOptions options: [AnyHashable: Any]) -> [URL] {
        var urls: [URL] = []
        let dictionary = options[UIApplication.LaunchOptionsKey.userActivityDictionary]
        if let dictionary = dictionary as? [AnyHashable: Any],
            let activity = dictionary[activityKey] as? NSUserActivity,
            let url = url(from: activity)
        {
            urls.append(url)
        }
        if let url = options[UIApplication.LaunchOptionsKey.url] as? URL {
            urls.append(url)
        }
        return urls
    }
}
