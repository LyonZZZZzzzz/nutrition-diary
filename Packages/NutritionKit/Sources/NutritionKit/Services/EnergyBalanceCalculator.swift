import Foundation

public struct EnergyBalanceCalculator: Sendable {
    public init() {}

    public func calculate(intakeKcal: Double?, activeKcal: Double?, basalKcal: Double?, balanceGoalKcal: Double? = nil) -> EnergyBalance {
        let totalBurn: Double?
        if let activeKcal, let basalKcal {
            totalBurn = activeKcal + basalKcal
        } else {
            totalBurn = nil
        }

        let activeBalance = intakeKcal.flatMap { intake in activeKcal.map { intake - $0 } }
        let totalBalance = intakeKcal.flatMap { intake in totalBurn.map { intake - $0 } }
        let suggestedIntake = totalBurn.flatMap { burn in balanceGoalKcal.map { burn + $0 } }
        let complete = intakeKcal != nil && activeKcal != nil && basalKcal != nil

        return EnergyBalance(
            intakeKcal: intakeKcal,
            activeKcal: activeKcal,
            basalKcal: basalKcal,
            totalBurnKcal: totalBurn,
            activeBalanceKcal: activeBalance,
            totalBalanceKcal: totalBalance,
            suggestedIntakeKcal: suggestedIntake,
            isComplete: complete
        )
    }
}
