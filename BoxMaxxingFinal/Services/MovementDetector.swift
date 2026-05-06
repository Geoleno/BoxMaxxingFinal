import CoreMedia

final class MovementDetector {

    private enum State {
        case idle
        case confirming(label: String, frames: Int, firstTimestamp: CMTime, confidenceSum: Float)
        case cooldown(until: CMTime)
    }

    private var state: State = .idle
    private let confirmFrames = 3
    private let cooldownSeconds: Double = 1.5
    private let correctThreshold: Float = 0.80

    func reset() { state = .idle }

    func process(prediction: FramePrediction,
                 timestamp: CMTime,
                 expectedMoveId: String) -> WrongMovement? {

        let isValidMove = findMove(prediction.label) != nil

        switch state {
        case .idle:
            guard isValidMove else { return nil }
            state = .confirming(label: prediction.label, frames: 1,
                                firstTimestamp: timestamp,
                                confidenceSum: prediction.confidence)
            return nil

        case .confirming(let label, let frames, let firstTimestamp, let confidenceSum):
            guard isValidMove, prediction.label == label else {
                state = .idle
                return nil
            }
            let newFrames = frames + 1
            let newSum    = confidenceSum + prediction.confidence
            guard newFrames >= confirmFrames else {
                state = .confirming(label: label, frames: newFrames,
                                    firstTimestamp: firstTimestamp,
                                    confidenceSum: newSum)
                return nil
            }
            let avgConfidence = newSum / Float(newFrames)
            let cooldownEnd   = CMTimeAdd(timestamp,
                                          CMTime(seconds: cooldownSeconds, preferredTimescale: 600))
            state = .cooldown(until: cooldownEnd)
            let matched = (label == expectedMoveId) && avgConfidence >= correctThreshold
            if findMove(expectedMoveId) == nil {
                assertionFailure("expectedMoveId '\(expectedMoveId)' not found in allMoves — check combo configuration")
            }
            guard !matched, let expectedMove = findMove(expectedMoveId) else { return nil }
            return WrongMovement(timestamp: firstTimestamp,
                                 expectedMove: expectedMove,
                                 detectedMoveId: label,
                                 confidence: avgConfidence)

        case .cooldown(let until):
            if CMTimeCompare(timestamp, until) >= 0 {
                state = .idle
                if isValidMove {
                    state = .confirming(label: prediction.label, frames: 1,
                                        firstTimestamp: timestamp,
                                        confidenceSum: prediction.confidence)
                }
            }
            return nil
        }
    }
}
