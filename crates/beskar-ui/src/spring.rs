//! Spring physics animation engine.
//! Adapted directly from the iRiS / minflair spring curves (`inir/modules/common/Appearance.qml` and `minflair/IrisStyle.qml`).
//!
//! Parameters:
//! - `stiffness` / `spring`: 3.2
//! - `damping`: 0.28
//! - `mass`: 1.0
//! - `epsilon`: 0.001

#[derive(Clone, Copy, Debug)]
pub struct SpringConfig {
    pub stiffness: f32,
    pub damping: f32,
    pub mass: f32,
    pub epsilon: f32,
}

impl Default for SpringConfig {
    fn default() -> Self {
        Self {
            stiffness: 180.0,
            damping: 24.0,
            mass: 1.0,
            epsilon: 0.05,
        }
    }
}

impl SpringConfig {
    /// Spatial snappy spring for dynamic island morphing (stiff & snappy)
    pub fn spatial() -> Self {
        Self {
            stiffness: 240.0,
            damping: 26.0,
            mass: 1.0,
            epsilon: 0.05,
        }
    }

    /// Gentle liquid spring for volume / slider smooth follow (smooth & organic)
    pub fn liquid() -> Self {
        Self {
            stiffness: 150.0,
            damping: 20.0,
            mass: 1.0,
            epsilon: 0.05,
        }
    }
}

/// A simulated 1D spring value with current position and velocity.
#[derive(Clone, Copy, Debug)]
pub struct SpringValue {
    pub current: f32,
    pub target: f32,
    pub velocity: f32,
    pub config: SpringConfig,
}

impl SpringValue {
    pub fn new(initial: f32, config: SpringConfig) -> Self {
        Self {
            current: initial,
            target: initial,
            velocity: 0.0,
            config,
        }
    }

    pub fn set_target(&mut self, target: f32) {
        self.target = target;
    }

    /// Advance spring simulation by delta time `dt` (in seconds).
    /// Uses standard semi-implicit Euler integration.
    /// Returns true if the spring is still actively moving, false if settled.
    pub fn step(&mut self, dt: f32) -> bool {
        let displacement = self.current - self.target;

        // F = -k * x - c * v
        let spring_force = -self.config.stiffness * displacement;
        let damping_force = -self.config.damping * self.velocity;
        let acceleration = (spring_force + damping_force) / self.config.mass;

        self.velocity += acceleration * dt;
        self.current += self.velocity * dt;

        if (self.current - self.target).abs() < self.config.epsilon && self.velocity.abs() < self.config.epsilon * 10.0 {
            self.current = self.target;
            self.velocity = 0.0;
            return false;
        }

        true
    }

    pub fn is_settled(&self) -> bool {
        (self.current - self.target).abs() < self.config.epsilon && self.velocity.abs() < self.config.epsilon
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_spring_converges_to_target() {
        let mut spring = SpringValue::new(0.0, SpringConfig::spatial());
        spring.set_target(100.0);

        let dt = 1.0 / 60.0; // 60 FPS frame time
        let mut steps = 0;
        while spring.step(dt) && steps < 600 {
            steps += 1;
        }

        assert!(spring.is_settled());
        assert!((spring.current - 100.0).abs() < 0.01);
    }
}

