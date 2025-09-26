//
//  PillarParsingUtility.swift
//  DayPlanner
//
//  Centralized utility for parsing and normalizing AI pillar creation responses
//

import Foundation

/// Centralized utility for parsing and normalizing AI pillar creation responses
struct PillarParsingUtility {
    
    // MARK: - Main Parsing Method
    
    /// Parse AI pillar response and create a fully populated Pillar with all metadata
    static func parsePillarFromAI(_ pillarData: [String: Any]) -> Pillar {
        // Validate and enhance the data first
        let validatedData = validateAndEnhancePillarData(pillarData)
        
        // Extract and normalize all fields with smart defaults
        let name = extractString(from: validatedData, key: "name") ?? "New Pillar"
        let description = extractString(from: validatedData, key: "description") ?? "AI-created pillar"
        let frequency = parseFrequency(from: validatedData["frequency"])
        let values = extractStringArray(from: validatedData, key: "values")
        let habits = extractStringArray(from: validatedData, key: "habits")
        let constraints = extractStringArray(from: validatedData, key: "constraints")
        let quietHours = extractQuietHours(from: validatedData)
        let wisdom = extractString(from: validatedData, key: "wisdom") ?? extractString(from: validatedData, key: "wisdomText")
        let emoji = extractString(from: validatedData, key: "emoji") ?? "🏛️"
        
        // Create the pillar with all metadata populated
        return Pillar(
            name: name,
            description: description,
            frequency: frequency,
            quietHours: quietHours,
            wisdomText: wisdom,
            values: values,
            habits: habits,
            constraints: constraints,
            color: CodableColor(.purple),
            emoji: emoji
        )
    }
    
    // MARK: - Field Extraction Methods
    
    private static func extractString(from data: [String: Any], key: String) -> String? {
        guard let value = data[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    private static func extractStringArray(from data: [String: Any], key: String) -> [String] {
        guard let array = data[key] as? [String] else { return [] }
        return array
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    private static func parseFrequency(from value: Any?) -> PillarFrequency {
        guard let frequencyString = value as? String else { return .weekly(1) }
        
        let lowercased = frequencyString.lowercased()
        
        switch lowercased {
        case "daily":
            return .daily
        case "weekly":
            return .weekly(1)
        case "monthly":
            return .monthly(1)
        case "as_needed", "as needed":
            return .asNeeded
        default:
            // Try to parse "Nx per week" or "Nx per month" format
            if lowercased.contains("per week") {
                let components = lowercased.components(separatedBy: " ")
                if let count = Int(components.first ?? "1") {
                    return .weekly(count)
                }
            } else if lowercased.contains("per month") {
                let components = lowercased.components(separatedBy: " ")
                if let count = Int(components.first ?? "1") {
                    return .monthly(count)
                }
            }
            return .weekly(1) // Default fallback
        }
    }
    
    private static func extractQuietHours(from data: [String: Any]) -> [TimeWindow] {
        // Try multiple possible keys for quiet hours
        let quietHoursData = data["quietHours"] ?? data["quiet_hours"] ?? data["quietHours"] ?? []
        
        guard let array = quietHoursData as? [[String: Any]] else { return [] }
        
        return array.compactMap { parseTimeWindow(from: $0) }
    }
    
    private static func parseTimeWindow(from data: [String: Any]) -> TimeWindow? {
        // Handle different possible formats
        if let startHour = data["startHour"] as? Int,
           let startMinute = data["startMinute"] as? Int,
           let endHour = data["endHour"] as? Int,
           let endMinute = data["endMinute"] as? Int {
            return TimeWindow(
                startHour: startHour,
                startMinute: startMinute,
                endHour: endHour,
                endMinute: endMinute
            )
        }
        
        // Handle string format like "06:00-08:00"
        if let timeString = data["start"] as? String,
           let endString = data["end"] as? String {
            if let startTime = parseTimeString(timeString),
               let endTime = parseTimeString(endString) {
                return TimeWindow(
                    startHour: startTime.hour,
                    startMinute: startTime.minute,
                    endHour: endTime.hour,
                    endMinute: endTime.minute
                )
            }
        }
        
        return nil
    }
    
    private static func parseTimeString(_ timeString: String) -> (hour: Int, minute: Int)? {
        let components = timeString.components(separatedBy: ":")
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else {
            return nil
        }
        return (hour: hour, minute: minute)
    }
    
    // MARK: - Validation Methods
    
    /// Validate that a pillar has all required metadata
    static func validatePillar(_ pillar: Pillar) -> PillarValidationResult {
        var issues: [String] = []
        var suggestions: [String] = []
        
        // Check for empty description
        if pillar.description.isEmpty || pillar.description == "AI-created pillar" {
            issues.append("Description is missing or generic")
            suggestions.append("Add a specific description of what this pillar represents")
        }
        
        // Check for missing values
        if pillar.values.isEmpty {
            suggestions.append("Consider adding core values this pillar represents")
        }
        
        // Check for missing habits
        if pillar.habits.isEmpty {
            suggestions.append("Consider adding specific habits to encourage")
        }
        
        // Check for missing constraints
        if pillar.constraints.isEmpty {
            suggestions.append("Consider adding constraints or boundaries")
        }
        
        // Check for missing quiet hours
        if pillar.quietHours.isEmpty {
            suggestions.append("Consider adding quiet hours to protect important time")
        }
        
        // Check for missing wisdom text
        if pillar.wisdomText?.isEmpty != false {
            suggestions.append("Consider adding a core principle or wisdom statement")
        }
        
        let completeness = calculateCompleteness(pillar)
        
        return PillarValidationResult(
            isValid: issues.isEmpty,
            issues: issues,
            suggestions: suggestions,
            completeness: completeness
        )
    }
    
    private static func calculateCompleteness(_ pillar: Pillar) -> Double {
        var score = 0.0
        let totalFields = 6.0
        
        // Description (required)
        if !pillar.description.isEmpty && pillar.description != "AI-created pillar" {
            score += 1.0
        }
        
        // Values (optional but recommended)
        if !pillar.values.isEmpty {
            score += 1.0
        }
        
        // Habits (optional but recommended)
        if !pillar.habits.isEmpty {
            score += 1.0
        }
        
        // Constraints (optional but recommended)
        if !pillar.constraints.isEmpty {
            score += 1.0
        }
        
        // Quiet hours (optional but recommended)
        if !pillar.quietHours.isEmpty {
            score += 1.0
        }
        
        // Wisdom text (optional but recommended)
        if pillar.wisdomText?.isEmpty == false {
            score += 1.0
        }
        
        return score / totalFields
    }
    
    // MARK: - Enhancement Methods
    
    /// Enhance a pillar with AI-generated metadata if missing
    static func enhancePillar(_ pillar: Pillar, with context: String) -> Pillar {
        var enhanced = pillar
        
        // Only enhance if the pillar is incomplete
        let validation = validatePillar(pillar)
        guard validation.completeness < 0.8 else { return pillar }
        
        // Generate missing metadata based on pillar name and description
        if enhanced.values.isEmpty {
            enhanced.values = generateValues(for: pillar.name, description: pillar.description)
        }
        
        if enhanced.habits.isEmpty {
            enhanced.habits = generateHabits(for: pillar.name, description: pillar.description)
        }
        
        if enhanced.constraints.isEmpty {
            enhanced.constraints = generateConstraints(for: pillar.name, description: pillar.description)
        }
        
        if enhanced.wisdomText?.isEmpty != false {
            enhanced.wisdomText = generateWisdom(for: pillar.name, description: pillar.description)
        }
        
        return enhanced
    }
    
    // MARK: - Validation and Fallback Methods
    
    /// Validate AI-generated pillar data and provide fallbacks
    static func validateAndEnhancePillarData(_ data: [String: Any]) -> [String: Any] {
        var validatedData = data
        
        // Validate and sanitize name
        if let name = data["name"] as? String {
            validatedData["name"] = sanitizeName(name)
        } else {
            validatedData["name"] = "New Pillar"
        }
        
        // Validate and sanitize description
        if let description = data["description"] as? String {
            validatedData["description"] = sanitizeDescription(description)
        } else {
            validatedData["description"] = "AI-created pillar"
        }
        
        // Validate frequency
        if let frequency = data["frequency"] as? String {
            validatedData["frequency"] = validateFrequency(frequency)
        } else {
            validatedData["frequency"] = "weekly"
        }
        
        // Validate and sanitize arrays
        validatedData["values"] = validateStringArray(data["values"], maxItems: 5)
        validatedData["habits"] = validateStringArray(data["habits"], maxItems: 5)
        validatedData["constraints"] = validateStringArray(data["constraints"], maxItems: 4)
        validatedData["quietHours"] = validateQuietHours(data["quietHours"])
        
        // Validate wisdom text
        if let wisdom = data["wisdom"] as? String {
            validatedData["wisdom"] = sanitizeWisdom(wisdom)
        } else {
            validatedData["wisdom"] = NSNull()
        }
        
        // Validate emoji
        if let emoji = data["emoji"] as? String {
            validatedData["emoji"] = validateEmoji(emoji)
        } else {
            validatedData["emoji"] = "🏛️"
        }
        
        return validatedData
    }
    
    private static func sanitizeName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = trimmed.replacingOccurrences(of: "\n", with: " ")
        return String(sanitized.prefix(24)) // Max 24 characters
    }
    
    private static func sanitizeDescription(_ description: String) -> String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = trimmed.replacingOccurrences(of: "\n", with: " ")
        return String(sanitized.prefix(200)) // Max 200 characters
    }
    
    private static func validateFrequency(_ frequency: String) -> String {
        let lowercased = frequency.lowercased()
        switch lowercased {
        case "daily", "weekly", "monthly", "as_needed", "as needed":
            return lowercased
        default:
            return "weekly" // Default fallback
        }
    }
    
    private static func validateStringArray(_ value: Any?, maxItems: Int) -> [String] {
        guard let array = value as? [String] else { return [] }
        
        return array
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(maxItems)
            .map { String($0.prefix(50)) } // Max 50 characters per item
    }
    
    private static func validateQuietHours(_ value: Any?) -> [[String: Any]] {
        guard let array = value as? [[String: Any]] else { return [] }
        
        let validHours: [[String: Any]] = array.compactMap { hourData in
            guard let startHour = hourData["startHour"] as? Int,
                  let startMinute = hourData["startMinute"] as? Int,
                  let endHour = hourData["endHour"] as? Int,
                  let endMinute = hourData["endMinute"] as? Int else {
                return nil
            }
            
            // Validate time ranges
            let validStartHour = max(0, min(23, startHour))
            let validStartMinute = max(0, min(59, startMinute))
            let validEndHour = max(0, min(23, endHour))
            let validEndMinute = max(0, min(59, endMinute))
            
            return [
                "startHour": validStartHour,
                "startMinute": validStartMinute,
                "endHour": validEndHour,
                "endMinute": validEndMinute
            ]
        }
        
        return Array(validHours.prefix(3)) // Max 3 quiet hour windows
    }
    
    private static func sanitizeWisdom(_ wisdom: String) -> String? {
        let trimmed = wisdom.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = trimmed.replacingOccurrences(of: "\n", with: " ")
        let limited = String(sanitized.prefix(100)) // Max 100 characters
        
        return limited.isEmpty ? nil : limited
    }
    
    private static func validateEmoji(_ emoji: String) -> String {
        let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if it's a valid emoji (basic validation)
        if trimmed.unicodeScalars.count == 1,
           let scalar = trimmed.unicodeScalars.first,
           scalar.properties.isEmoji {
            return trimmed
        }
        
        // Fallback to default emoji
        return "🏛️"
    }
    
    private static func generateValues(for name: String, description: String) -> [String] {
        // Simple heuristic-based value generation
        let lowercased = name.lowercased()
        
        if lowercased.contains("health") || lowercased.contains("exercise") {
            return ["Vitality", "Discipline", "Well-being"]
        } else if lowercased.contains("work") || lowercased.contains("career") {
            return ["Excellence", "Growth", "Impact"]
        } else if lowercased.contains("family") || lowercased.contains("relationship") {
            return ["Connection", "Love", "Support"]
        } else if lowercased.contains("learning") || lowercased.contains("education") {
            return ["Curiosity", "Growth", "Knowledge"]
        } else {
            return ["Integrity", "Purpose", "Balance"]
        }
    }
    
    private static func generateHabits(for name: String, description: String) -> [String] {
        let lowercased = name.lowercased()
        
        if lowercased.contains("health") || lowercased.contains("exercise") {
            return ["Daily movement", "Proper nutrition", "Adequate sleep"]
        } else if lowercased.contains("work") || lowercased.contains("career") {
            return ["Deep work sessions", "Regular breaks", "Skill development"]
        } else if lowercased.contains("family") || lowercased.contains("relationship") {
            return ["Quality time", "Active listening", "Regular check-ins"]
        } else if lowercased.contains("learning") || lowercased.contains("education") {
            return ["Daily reading", "Practice sessions", "Reflection time"]
        } else {
            return ["Morning routine", "Evening reflection", "Weekly review"]
        }
    }
    
    private static func generateConstraints(for name: String, description: String) -> [String] {
        let lowercased = name.lowercased()
        
        if lowercased.contains("health") || lowercased.contains("exercise") {
            return ["No intense workouts after 9pm", "Listen to body signals", "Rest when needed"]
        } else if lowercased.contains("work") || lowercased.contains("career") {
            return ["No work after 6pm", "Protect deep work time", "Limit meetings"]
        } else if lowercased.contains("family") || lowercased.contains("relationship") {
            return ["No devices during family time", "Be fully present", "Respect boundaries"]
        } else if lowercased.contains("learning") || lowercased.contains("education") {
            return ["Focus on one topic at a time", "Apply learning immediately", "Take breaks"]
        } else {
            return ["Maintain balance", "Respect limits", "Prioritize well-being"]
        }
    }
    
    private static func generateWisdom(for name: String, description: String) -> String {
        let lowercased = name.lowercased()
        
        if lowercased.contains("health") || lowercased.contains("exercise") {
            return "Strong body, clear mind."
        } else if lowercased.contains("work") || lowercased.contains("career") {
            return "Excellence is a habit, not an accident."
        } else if lowercased.contains("family") || lowercased.contains("relationship") {
            return "Love is the foundation of everything."
        } else if lowercased.contains("learning") || lowercased.contains("education") {
            return "Knowledge is power, but wisdom is the key."
        } else {
            return "Live with intention and purpose."
        }
    }
}

// MARK: - Supporting Types

struct PillarValidationResult {
    let isValid: Bool
    let issues: [String]
    let suggestions: [String]
    let completeness: Double
    
    var completenessPercentage: Int {
        Int(completeness * 100)
    }
    
    var needsEnhancement: Bool {
        completeness < 0.8
    }
}

// MARK: - Extensions

extension Pillar {
    /// Create a pillar from AI response data using the centralized parser
    static func fromAI(_ data: [String: Any]) -> Pillar {
        return PillarParsingUtility.parsePillarFromAI(data)
    }
    
    /// Validate this pillar's completeness
    func validate() -> PillarValidationResult {
        return PillarParsingUtility.validatePillar(self)
    }
    
    /// Enhance this pillar with missing metadata
    func enhance(with context: String = "") -> Pillar {
        return PillarParsingUtility.enhancePillar(self, with: context)
    }
}
