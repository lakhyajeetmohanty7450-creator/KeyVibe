import Foundation
import AVFoundation

let packDir = "/Applications/KeyVibe.app/Contents/Resources/SoundPacks/cherry-mx-blue"
let fileURL = URL(fileURLWithPath: "\(packDir)/medium_press_alpha.wav")
print("Testing file exists: \(FileManager.default.fileExists(atPath: fileURL.path))")

do {
    let file = try AVAudioFile(forReading: fileURL)
    print("File format: \(file.processingFormat)")
    print("Length: \(file.length) frames")
} catch {
    print("Error reading WAV: \(error)")
}
