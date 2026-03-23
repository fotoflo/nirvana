import SwiftUI
import SpriteKit

// MARK: - GLSL Shader Source

private let cloudShaderSource = """
// Value noise hash
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Smooth value noise
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// fBm - 4 octaves
float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < 4; i++) {
        value += amplitude * noise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

void main() {
    vec2 uv = v_tex_coord;
    float time = u_time * 0.03;

    // Animate UV
    vec2 animated_uv = uv * 3.0 + vec2(time, time * 0.7);

    // Cloud density
    float density = fbm(animated_uv);
    density += 0.3 * fbm(animated_uv * 2.5 + vec2(time * 0.5, -time * 0.3));
    density = clamp(density, 0.0, 1.0);

    // Disperse effect: push clouds away from u_center
    float disperse = u_disperse;
    if (disperse > 0.0) {
        vec2 center = u_center;
        vec2 dir = uv - center;
        float dist = length(dir);
        float push = disperse * smoothstep(0.0, 0.6, 1.0 - dist);
        density *= mix(1.0, smoothstep(0.0, 0.3, dist), disperse);
        animated_uv += normalize(dir + 0.001) * push * 1.5;
        density = mix(density, fbm(animated_uv), disperse * 0.5);
        density = clamp(density, 0.0, 1.0);
    }

    // Color palette: deep indigo -> purple -> gold
    vec3 indigo = vec3(0.102, 0.102, 0.180);
    vec3 purple = vec3(0.25, 0.15, 0.35);
    vec3 gold   = vec3(0.788, 0.659, 0.298);

    vec3 color = mix(indigo, purple, smoothstep(0.2, 0.5, density));
    color = mix(color, gold, smoothstep(0.55, 0.8, density) * 0.4);

    // Subtle vignette
    float vignette = 1.0 - 0.3 * length(uv - 0.5);
    color *= vignette;

    gl_FragColor = vec4(color, 1.0);
}
"""

// MARK: - CloudScene

/// SpriteKit scene rendering a procedural cloud background via GPU shader.
/// Uses fBm noise colored in the Nirvana indigo-to-gold palette.
/// Performance target: <1% GPU via simple value noise and 4 octave fBm.
class CloudScene: SKScene {

    private var backgroundNode: SKSpriteNode!
    private var timeUniform: SKUniform!
    private var disperseUniform: SKUniform!
    private var centerUniform: SKUniform!
    private var startTime: TimeInterval = 0

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        backgroundColor = .black
        scaleMode = .resizeFill

        // Create full-screen sprite
        backgroundNode = SKSpriteNode(color: .clear, size: size)
        backgroundNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        backgroundNode.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        addChild(backgroundNode)

        // Uniforms
        timeUniform = SKUniform(name: "u_time", float: 0)
        disperseUniform = SKUniform(name: "u_disperse", float: 0)
        centerUniform = SKUniform(name: "u_center", vectorFloat2: SIMD2<Float>(0.5, 0.5))

        // Shader
        let shader = SKShader(source: cloudShaderSource)
        shader.uniforms = [timeUniform, disperseUniform, centerUniform]
        backgroundNode.shader = shader
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        backgroundNode?.size = size
        backgroundNode?.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    override func update(_ currentTime: TimeInterval) {
        if startTime == 0 { startTime = currentTime }
        let elapsed = Float(currentTime - startTime)
        timeUniform.floatValue = elapsed
    }

    // MARK: - Focus Collapse Disperse

    /// Animate clouds parting from the selected grid cell center.
    /// - Parameters:
    ///   - centerX: Normalized X position (0-1) of the selected cell.
    ///   - centerY: Normalized Y position (0-1) of the selected cell.
    func disperseClouds(from centerX: Float, centerY: Float) {
        centerUniform.vectorFloat2Value = SIMD2<Float>(centerX, centerY)

        // Animate disperse from 0 → 1 over 0.5s
        let rampUp = SKAction.customAction(withDuration: 0.5) { [weak self] _, elapsed in
            let progress = Float(elapsed / 0.5)
            self?.disperseUniform.floatValue = progress
        }
        run(rampUp)
    }

    /// Reset clouds to their undispersed state.
    func resetDisperse() {
        let rampDown = SKAction.customAction(withDuration: 0.4) { [weak self] _, elapsed in
            let progress = 1.0 - Float(elapsed / 0.4)
            self?.disperseUniform.floatValue = max(progress, 0)
        }
        run(rampDown)
    }
}

// MARK: - CloudBackgroundView

/// SwiftUI wrapper around CloudScene for embedding the procedural cloud background.
struct CloudBackgroundView: View {
    @State private var scene: CloudScene = {
        let s = CloudScene()
        s.scaleMode = .resizeFill
        return s
    }()

    var body: some View {
        SpriteView(scene: scene)
            .ignoresSafeArea()
    }

    /// Access the underlying scene to trigger disperse effects.
    var cloudScene: CloudScene { scene }
}
