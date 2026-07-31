import EventKit
import Foundation

struct TodoRequest: Decodable {
    let action: String
    let id: String?
    let listId: String?
    let title: String?
    let notes: String?
    let due: String?
    let allDay: Bool?
    let priority: Int?
    let completed: Bool?

    enum CodingKeys: String, CodingKey {
        case action, id, title, notes, due, priority, completed
        case listId = "list_id"
        case allDay = "all_day"
    }
}

enum TodoFailure: LocalizedError {
    case invalidRequest(String)
    case noICloudLists
    case listNotFound(String)
    case reminderNotFound(String)
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .invalidRequest(let message): return message
        case .noICloudLists: return "没有找到可访问的 iCloud 提醒事项列表"
        case .listNotFound(let identifier): return "找不到列表：\(identifier)"
        case .reminderNotFound(let identifier): return "找不到任务：\(identifier)"
        case .accessDenied: return "没有获得提醒事项完整访问权限"
        }
    }
}

@main
struct TodoReminders {
    static let store = EKEventStore()

    static func main() async {
        do {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            guard !input.isEmpty else {
                throw TodoFailure.invalidRequest("请求为空")
            }
            let request = try JSONDecoder().decode(TodoRequest.self, from: input)
            guard try await store.requestFullAccessToReminders() else {
                throw TodoFailure.accessDenied
            }
            let result = try await perform(request)
            try write(result)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            try? write(["ok": false, "error": message])
            Foundation.exit(1)
        }
    }

    static func perform(_ request: TodoRequest) async throws -> [String: Any] {
        let calendars = iCloudCalendars()
        guard !calendars.isEmpty else { throw TodoFailure.noICloudLists }

        switch request.action {
        case "snapshot":
            let reminders = await fetchReminders(calendars: calendars)
            return [
                "ok": true,
                "lists": calendars
                    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                    .map(listObject),
                "tasks": reminders.map(taskObject),
            ]
        case "create":
            let calendar = try calendar(identifier: required(request.listId, "缺少 list_id"), in: calendars)
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = calendar
            try apply(request, to: reminder, creating: true, calendars: calendars)
            try store.save(reminder, commit: true)
            return ["ok": true, "task": taskObject(reminder)]
        case "update":
            let reminder = try findReminder(required(request.id, "缺少任务 id"))
            try apply(request, to: reminder, creating: false, calendars: calendars)
            try store.save(reminder, commit: true)
            return ["ok": true, "task": taskObject(reminder)]
        case "complete":
            let reminder = try findReminder(required(request.id, "缺少任务 id"))
            let completed = request.completed ?? !reminder.isCompleted
            reminder.isCompleted = completed
            reminder.completionDate = completed ? Date() : nil
            try store.save(reminder, commit: true)
            return ["ok": true, "task": taskObject(reminder)]
        case "delete":
            let reminder = try findReminder(required(request.id, "缺少任务 id"))
            try store.remove(reminder, commit: true)
            return ["ok": true]
        default:
            throw TodoFailure.invalidRequest("未知操作：\(request.action)")
        }
    }

    static func iCloudCalendars() -> [EKCalendar] {
        store.calendars(for: .reminder).filter { calendar in
            calendar.source.title.caseInsensitiveCompare("iCloud") == .orderedSame
        }
    }

    static func fetchReminders(calendars: [EKCalendar]) async -> [EKReminder] {
        let predicate = store.predicateForReminders(in: calendars)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    static func listObject(_ calendar: EKCalendar) -> [String: Any] {
        ["id": calendar.calendarIdentifier, "name": calendar.title]
    }

    static func taskObject(_ reminder: EKReminder) -> [String: Any] {
        var object: [String: Any] = [
            "id": reminder.calendarItemIdentifier,
            "list_id": reminder.calendar.calendarIdentifier,
            "title": reminder.title ?? "",
            "notes": reminder.notes ?? "",
            "priority": reminder.priority,
            "completed": reminder.isCompleted,
            "all_day": reminder.dueDateComponents.map { $0.hour == nil } ?? false,
        ]
        if let components = reminder.dueDateComponents,
           let date = Calendar.current.date(from: components) {
            object["due"] = ISO8601DateFormatter().string(from: date)
        } else {
            object["due"] = NSNull()
        }
        return object
    }

    static func apply(
        _ request: TodoRequest,
        to reminder: EKReminder,
        creating: Bool,
        calendars: [EKCalendar]
    ) throws {
        if let listId = request.listId {
            reminder.calendar = try calendar(identifier: listId, in: calendars)
        }
        if let title = request.title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw TodoFailure.invalidRequest("标题不能为空") }
            reminder.title = trimmed
        } else if creating {
            throw TodoFailure.invalidRequest("缺少任务标题")
        }
        if let notes = request.notes { reminder.notes = notes }
        if let priority = request.priority {
            guard (0...9).contains(priority) else {
                throw TodoFailure.invalidRequest("优先级必须在 0 到 9 之间")
            }
            reminder.priority = priority
        }
        if request.due != nil {
            if let value = request.due, !value.isEmpty {
                reminder.dueDateComponents = try dueComponents(value, allDay: request.allDay ?? false)
            } else {
                reminder.dueDateComponents = nil
            }
        }
    }

    static func dueComponents(_ value: String, allDay: Bool) throws -> DateComponents {
        let formats = allDay
            ? ["yyyy-MM-dd"]
            : ["yyyy-MM-dd HH:mm", "yyyy-MM-dd"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                var units: Set<Calendar.Component> = [.year, .month, .day]
                if !allDay && format.contains("HH") {
                    units.formUnion([.hour, .minute])
                }
                var components = Calendar.current.dateComponents(units, from: date)
                components.calendar = Calendar.current
                components.timeZone = .current
                return components
            }
        }
        throw TodoFailure.invalidRequest("日期格式应为 YYYY-MM-DD 或 YYYY-MM-DD HH:MM")
    }

    static func calendar(identifier: String, in calendars: [EKCalendar]) throws -> EKCalendar {
        guard let calendar = calendars.first(where: { $0.calendarIdentifier == identifier }) else {
            throw TodoFailure.listNotFound(identifier)
        }
        return calendar
    }

    static func findReminder(_ identifier: String) throws -> EKReminder {
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw TodoFailure.reminderNotFound(identifier)
        }
        guard reminder.calendar.source.title.caseInsensitiveCompare("iCloud") == .orderedSame else {
            throw TodoFailure.invalidRequest("只允许操作 iCloud 提醒事项")
        }
        return reminder
    }

    static func required(_ value: String?, _ message: String) throws -> String {
        guard let value, !value.isEmpty else { throw TodoFailure.invalidRequest(message) }
        return value
    }

    static func write(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}
