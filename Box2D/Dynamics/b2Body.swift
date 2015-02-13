/**
Copyright (c) 2006-2014 Erin Catto http://www.box2d.org
Copyright (c) 2015 - Yohei Yoshihara

This software is provided 'as-is', without any express or implied
warranty.  In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
claim that you wrote the original software. If you use this software
in a product, an acknowledgment in the product documentation would be
appreciated but is not required.

2. Altered source versions must be plainly marked as such, and must not be
misrepresented as being the original software.

3. This notice may not be removed or altered from any source distribution.

This version of box2d was developed by Yohei Yoshihara. It is based upon
the original C++ code written by Erin Catto.
*/

import Foundation

/// The body type.
/// static: zero mass, zero velocity, may be manually moved
/// kinematic: zero mass, non-zero velocity set by user, moved by solver
/// dynamic: positive mass, non-zero velocity determined by forces, moved by solver
public enum b2BodyType : Int, Printable {
  case staticBody = 0
  case kinematicBody
  case dynamicBody
  
  // TODO_ERIN
  //b2_bulletBody,
  
  public var description: String {
    switch self {
    case staticBody: return "staticBody"
    case kinematicBody: return "kinematicBody"
    case dynamicBody: return "dynamicBody"
    }
  }
}

/// A body definition holds all the data needed to construct a rigid body.
/// You can safely re-use body definitions. Shapes are added to a body after construction.
public class b2BodyDef {
  /// This constructor sets the body definition default values.
  public init() {
  }
  
  /// The body type: static, kinematic, or dynamic.
  /// Note: if a dynamic body would have zero mass, the mass is set to one.
  public var type = b2BodyType.staticBody
  
  /// The world position of the body. Avoid creating bodies at the origin
  /// since this can lead to many overlapping shapes.
  public var position = b2Vec2()
  
  /// The world angle of the body in radians.
  public var angle: b2Float = 0.0
  
  /// The linear velocity of the body's origin in world co-ordinates.
  public var linearVelocity = b2Vec2()
  
  /// The angular velocity of the body.
  public var angularVelocity: b2Float = 0.0
  
  /// Linear damping is use to reduce the linear velocity. The damping parameter
  /// can be larger than 1.0f but the damping effect becomes sensitive to the
  /// time step when the damping parameter is large.
  public var linearDamping: b2Float = 0.0
  
  /// Angular damping is use to reduce the angular velocity. The damping parameter
  /// can be larger than 1.0f but the damping effect becomes sensitive to the
  /// time step when the damping parameter is large.
  public var angularDamping: b2Float = 0.0
  
  /// Set this flag to false if this body should never fall asleep. Note that
  /// this increases CPU usage.
  public var allowSleep = true
  
  /// Is this body initially awake or sleeping?
  public var awake = true
  
  /// Should this body be prevented from rotating? Useful for characters.
  public var fixedRotation = false
  
  /// Is this a fast moving body that should be prevented from tunneling through
  /// other moving bodies? Note that all bodies are prevented from tunneling through
  /// kinematic and static bodies. This setting is only considered on dynamic bodies.
  /// @warning You should use this flag sparingly since it increases processing time.
  public var bullet = false
  
  /// Does this body start out active?
  public var active = true
  
  /// Use this to store application specific body data.
  public var userData : AnyObject? = nil
  
  /// Scale the gravity applied to this body.
  public var gravityScale: b2Float = 1.0
}

// MARK: -
/// A rigid body. These are created via b2World::createBody.
public class b2Body : Printable {
  /// Creates a fixture and attach it to this body. Use this function if you need
  /// to set some fixture parameters, like friction. Otherwise you can create the
  /// fixture directly from a shape.
  /// If the density is non-zero, this function automatically updates the mass of the body.
  /// Contacts are not created until the next time step.
  /// @param def the fixture definition.
  /// @warning This function is locked during callbacks.
  public func createFixture(def: b2FixtureDef) -> b2Fixture {
    assert(m_world.isLocked == false)
    if m_world.isLocked == true {
      fatalError("world is locked")
    }
    
    var fixture = b2Fixture(body: self, def: def)
    //fixture.Create(self, def: def)
    
    if (m_flags & Flags.e_activeFlag) != 0 {
      let broadPhase = m_world.m_contactManager.m_broadPhase
      fixture.createProxies(broadPhase, xf: m_xf)
    }
    
    fixture.m_next = m_fixtureList
    m_fixtureList = fixture
    ++m_fixtureCount
    
    fixture.m_body = self
    
    // Adjust mass properties if needed.
    if fixture.m_density > 0.0 {
      resetMassData()
    }
    
    // Let the world know we have a new fixture. This will cause new contacts
    // to be created at the beginning of the next time step.
    m_world.m_flags |= b2World.Flags.e_newFixture
    
    return fixture
  }
  
  /// Creates a fixture from a shape and attach it to this body.
  /// This is a convenience function. Use b2FixtureDef if you need to set parameters
  /// like friction, restitution, user data, or filtering.
  /// If the density is non-zero, this function automatically updates the mass of the body.
  /// @param shape the shape to be cloned.
  /// @param density the shape density (set to zero for static bodies).
  /// @warning This function is locked during callbacks.
  public func createFixture(#shape: b2Shape, density: b2Float) -> b2Fixture {
    var def = b2FixtureDef()
    def.shape = shape
    def.density = density
    return createFixture(def)
  }
  
  /// Destroy a fixture. This removes the fixture from the broad-phase and
  /// destroys all contacts associated with this fixture. This will
  /// automatically adjust the mass of the body if the body is dynamic and the
  /// fixture has positive density.
  /// All fixtures attached to a body are implicitly destroyed when the body is destroyed.
  /// @param fixture the fixture to be removed.
  /// @warning This function is locked during callbacks.
  public func destroyFixture(fixture: b2Fixture) {
    assert(m_world.isLocked == false)
    if m_world.isLocked == true {
      return
    }
    
    assert(fixture.m_body === self)
    
    // Remove the fixture from this body's singly linked list.
    assert(m_fixtureCount > 0)
    var found = false
    var prev: b2Fixture? = nil
    for (var f = m_fixtureList; f != nil; f = f!.m_next) {
      if f === fixture {
        if let prev = prev {
          prev.m_next = f!.m_next
        }
        else {
          m_fixtureList = f!.m_next
        }
        found = true
      }
      prev = f
    }
    
    // You tried to remove a shape that is not attached to this body.
    assert(found)
    
    // Destroy any contacts associated with the fixture.
    var edge: b2ContactEdge? = m_contactList
    while edge != nil {
      var c = edge!.contact
      edge = edge!.next
      
      let fixtureA = c.fixtureA
      let fixtureB = c.fixtureB
      
      if fixture === fixtureA || fixture === fixtureB {
        // This destroys the contact and removes it from
        // this body's contact list.
        m_world.m_contactManager.destroy(c)
      }
    }
    
    if (m_flags & Flags.e_activeFlag) != 0 {
      let broadPhase = m_world.m_contactManager.m_broadPhase
      fixture.destroyProxies(broadPhase)
    }
    
    fixture.destroy()
    fixture.m_next = nil
    
    --m_fixtureCount
    
    // Reset the mass data.
    resetMassData()
  }
  
  /**
  Set the position of the body's origin and rotation.
  Manipulating a body's transform may cause non-physical behavior.
  Note: contacts are updated on the next call to b2World::Step.

  :param: position the world position of the body's local origin.
  :param: angle the world rotation in radians.
  */
  public func setTransform(#position: b2Vec2, angle: b2Float) {
    assert(m_world.isLocked == false)
    if m_world.isLocked == true {
      return
    }
    
    m_xf.q.set(angle)
    m_xf.p = position
    
    m_sweep.c = b2Mul(m_xf, m_sweep.localCenter)
    m_sweep.a = angle
    
    m_sweep.c0 = m_sweep.c
    m_sweep.a0 = angle
    
    let broadPhase = m_world.m_contactManager.m_broadPhase
    for (var f: b2Fixture? = m_fixtureList; f != nil; f = f!.m_next) {
      f!.synchronize(broadPhase, m_xf, m_xf)
    }
  }
  
  /// Get the body world transform for the body's origin.
  public var transform: b2Transform {
    return m_xf
  }
  
  /// Get the world body origin position.
  public var position: b2Vec2 {
    return m_xf.p
  }
  
  /// Get the current world rotation angle in radians.
  public var angle: b2Float {
    return m_sweep.a
  }
  
  /// Get the world position of the center of mass.
  public var worldCenter: b2Vec2 {
    return m_sweep.c
  }
  
  /// Get the local position of the center of mass.
  public var localCenter: b2Vec2 {
    return m_sweep.localCenter
  }
  
  /**
  Set the linear velocity of the center of mass.

  :param: v the new linear velocity of the center of mass.
  */
  public func setLinearVelocity(v: b2Vec2) {
    if m_type == b2BodyType.staticBody {
      return
    }
    
    if b2Dot(v,v) > 0.0 {
      setAwake(true)
    }
    
    m_linearVelocity = v
  }
  
  /// the linear velocity of the center of mass.
  public var linearVelocity: b2Vec2 {
    get {
      return m_linearVelocity
    }
    set {
      setLinearVelocity(newValue)
    }
  }
  
  /**
  Set the angular velocity.
  
  :param: omega the new angular velocity in radians/second.
  */
  public func setAngularVelocity(omega: b2Float) {
    if m_type == b2BodyType.staticBody {
      return
    }
    
    if omega * omega > 0.0 {
      setAwake(true)
    }
    
    m_angularVelocity = omega
  }
  
  /// Get the angular velocity in radians/second.
  public var angularVelocity: b2Float {
    get {
      return m_angularVelocity
    }
    set {
      setAngularVelocity(newValue)
    }
  }
  
  /**
  Apply a force at a world point. If the force is not
  applied at the center of mass, it will generate a torque and
  affect the angular velocity. This wakes up the body.
  
  :param: force the world force vector, usually in Newtons (N).
  :param: point the world position of the point of application.
  :param: wake also wake up the body
  */
  public func applyForce(force: b2Vec2, point: b2Vec2, wake: Bool) {
    if m_type != b2BodyType.dynamicBody {
      return
    }
    
    if wake && (m_flags & Flags.e_awakeFlag) == 0 {
      setAwake(true)
    }
    
    // Don't accumulate a force if the body is sleeping.
    if (m_flags & Flags.e_awakeFlag) != 0 {
      m_force += force
      m_torque += b2Cross(point - m_sweep.c, force)
    }
  }
  
  /**
  Apply a force to the center of mass. This wakes up the body.
  
  :param: force the world force vector, usually in Newtons (N).
  :param: wake also wake up the body
  */
  public func applyForceToCenter(force: b2Vec2, wake: Bool) {
    if m_type != b2BodyType.dynamicBody {
      return
    }
        
    if wake && (m_flags & Flags.e_awakeFlag) == 0 {
      setAwake(true)
    }
        
    // Don't accumulate a force if the body is sleeping
    if (m_flags & Flags.e_awakeFlag) != 0 {
      m_force += force
    }
  }
  
  /**
  Apply a torque. This affects the angular velocity
  without affecting the linear velocity of the center of mass.
  This wakes up the body.
  
  :param: torque about the z-axis (out of the screen), usually in N-m.
  :param: wake also wake up the body
  */
  public func applyTorque(torque: b2Float, wake: Bool) {
    if m_type != b2BodyType.dynamicBody {
      return
    }
      
    if wake && (m_flags & Flags.e_awakeFlag) == 0 {
      setAwake(true)
    }
      
    // Don't accumulate a force if the body is sleeping
    if (m_flags & Flags.e_awakeFlag) != 0 {
      m_torque += torque
    }
  }
  
  /**
  Apply an impulse at a point. This immediately modifies the velocity.
  It also modifies the angular velocity if the point of application
  is not at the center of mass. This wakes up the body.
  
  :param: impulse the world impulse vector, usually in N-seconds or kg-m/s.
  :param: point the world position of the point of application.
  :param: wake also wake up the body
  */
  public func applyLinearImpulse(impulse: b2Vec2, point: b2Vec2, wake: Bool) {
    if m_type != b2BodyType.dynamicBody {
      return
    }
    
    if wake && (m_flags & Flags.e_awakeFlag) == 0 {
      setAwake(true)
    }
    
    // Don't accumulate velocity if the body is sleeping
    if (m_flags & Flags.e_awakeFlag) != 0 {
      m_linearVelocity += m_invMass * impulse
      m_angularVelocity += m_invI * b2Cross(point - m_sweep.c, impulse)
    }
  }
  
  /**
  Apply an angular impulse.

  :param: impulse the angular impulse in units of kg*m*m/s
  :param: wake also wake up the body
  */
  public func applyAngularImpulse(impulse: b2Float, wake: Bool) {
    if m_type != b2BodyType.dynamicBody {
      return
    }
        
    if wake && (m_flags & Flags.e_awakeFlag) == 0 {
      setAwake(true)
    }
        
    // Don't accumulate velocity if the body is sleeping
    if (m_flags & Flags.e_awakeFlag) != 0 {
      m_angularVelocity += m_invI * impulse
    }
  }
  
  /// Get the total mass of the body, usually in kilograms (kg).
  public var mass: b2Float {
    return m_mass
  }
  
  /// Get the rotational inertia of the body about the local origin, usually in kg-m^2.
  public var inertia: b2Float {
    return m_I + m_mass * b2Dot(m_sweep.localCenter, m_sweep.localCenter)
  }
  
  /// the mass data of the body. a struct containing the mass, inertia and center of the body.
  public var massData: b2MassData {
    get {
      var data = b2MassData()
      data.mass = m_mass
      data.I = m_I + m_mass * b2Dot(m_sweep.localCenter, m_sweep.localCenter)
      data.center = m_sweep.localCenter
      return data
    }
    set {
      setMassData(newValue)
    }
  }
  
  /**
  Set the mass properties to override the mass properties of the fixtures.
  Note that this changes the center of mass position.
  Note that creating or destroying fixtures can also alter the mass.
  This function has no effect if the body isn't dynamic.
  
  :param: massData the mass properties.
  */
  public func setMassData(massData: b2MassData) {
    assert(m_world.isLocked == false)
    if m_world.isLocked == true {
      return
    }
      
    if m_type != b2BodyType.dynamicBody {
      return
    }
      
    m_invMass = 0.0
    m_I = 0.0
    m_invI = 0.0
      
    m_mass = massData.mass
    if m_mass <= 0.0 {
      m_mass = 1.0
    }
      
    m_invMass = 1.0 / m_mass
      
    if massData.I > 0.0 && (m_flags & b2Body.Flags.e_fixedRotationFlag) == 0 {
      m_I = massData.I - m_mass * b2Dot(massData.center, massData.center)
      assert(m_I > 0.0)
      m_invI = 1.0 / m_I
    }
      
    // Move center of mass.
    let oldCenter = m_sweep.c
    m_sweep.localCenter =  massData.center
    m_sweep.c0 = b2Mul(m_xf, m_sweep.localCenter)
    m_sweep.c = m_sweep.c0
      
    // Update center of mass velocity.
    m_linearVelocity += b2Cross(m_angularVelocity, m_sweep.c - oldCenter)
  }
  
  /// This resets the mass properties to the sum of the mass properties of the fixtures.
  /// This normally does not need to be called unless you called SetMassData to override
  /// the mass and you later want to reset the mass.
  public func resetMassData() {
    // Compute mass data from shapes. Each shape has its own density.
    m_mass = 0.0
    m_invMass = 0.0
    m_I = 0.0
    m_invI = 0.0
    m_sweep.localCenter.setZero()
        
    // Static and kinematic bodies have zero mass.
    if m_type == b2BodyType.staticBody || m_type == b2BodyType.kinematicBody {
      m_sweep.c0 = m_xf.p
      m_sweep.c = m_xf.p
      m_sweep.a0 = m_sweep.a
      return
    }
        
    assert(m_type == b2BodyType.dynamicBody)
        
    // Accumulate mass over all fixtures.
    var localCenter = b2Vec2_zero
    for (var f: b2Fixture? = m_fixtureList; f != nil; f = f!.m_next) {
      if f!.m_density == 0.0 {
        continue
      }
      
      var massData = f!.massData
      m_mass += massData.mass
      localCenter += massData.mass * massData.center
      m_I += massData.I
    }
        
    // Compute center of mass.
    if m_mass > 0.0 {
      m_invMass = 1.0 / m_mass
      localCenter *= m_invMass
    }
    else {
      // Force all dynamic bodies to have a positive mass.
      m_mass = 1.0
      m_invMass = 1.0
    }
        
    if m_I > 0.0 && (m_flags & Flags.e_fixedRotationFlag) == 0 {
      // Center the inertia about the center of mass.
      m_I -= m_mass * b2Dot(localCenter, localCenter)
      assert(m_I > 0.0)
      m_invI = 1.0 / m_I
    }
    else {
      m_I = 0.0
      m_invI = 0.0
    }
        
    // Move center of mass.
    let oldCenter = m_sweep.c
    m_sweep.localCenter = localCenter
    m_sweep.c0 = b2Mul(m_xf, m_sweep.localCenter)
    m_sweep.c = m_sweep.c0
        
    // Update center of mass velocity.
    m_linearVelocity += b2Cross(m_angularVelocity, m_sweep.c - oldCenter)
  }
  
  /**
  Get the world coordinates of a point given the local coordinates.

  :param: localPoint a point on the body measured relative the the body's origin.
  :returns: the same point expressed in world coordinates.
  */
  public func getWorldPoint(localPoint: b2Vec2) -> b2Vec2 {
    return b2Mul(m_xf, localPoint)
  }
  
  /**
  Get the world coordinates of a vector given the local coordinates.

  :param: localVector a vector fixed in the body.
  :returns: the same vector expressed in world coordinates.
  */
  public func getWorldVector(localVector: b2Vec2) -> b2Vec2 {
    return b2Mul(m_xf.q, localVector)
  }
  
  /**
  Gets a local point relative to the body's origin given a world point.

  :param: a point in world coordinates.
  :returns: the corresponding local point relative to the body's origin.
  */
  public func getLocalPoint(worldPoint: b2Vec2) -> b2Vec2 {
    return b2MulT(m_xf, worldPoint)
  }
  
  /**
  Gets a local vector given a world vector.
  
  :param: a vector in world coordinates.
  :returns: the corresponding local vector.
  */
  public func getLocalVector(worldVector: b2Vec2) -> b2Vec2 {
    return b2MulT(m_xf.q, worldVector)
  }
  
  /**
  Get the world linear velocity of a world point attached to this body.
  
  :param: a point in world coordinates.
  :returns: the world velocity of a point.
  */
  public func getLinearVelocityFromWorldPoint(worldPoint: b2Vec2) -> b2Vec2 {
    return m_linearVelocity + b2Cross(m_angularVelocity, worldPoint - m_sweep.c)
  }
  
  /**
  Get the world velocity of a local point.

  :param: a point in local coordinates.
  :returns: the world velocity of a point.
  */
  public func getLinearVelocityFromLocalPoint(localPoint: b2Vec2) -> b2Vec2 {
      return getLinearVelocityFromWorldPoint(getWorldPoint(localPoint))
  }
  
  /// Get the linear damping of the body.
  public var linearDamping: b2Float {
    get {
      return m_linearDamping
    }
    set {
      setLinearDamping(newValue)
    }
  }
  
  /// Set the linear damping of the body.
  public func setLinearDamping(linearDamping: b2Float) {
    m_linearDamping = linearDamping
  }
  
  /// Get the angular damping of the body.
  public var angularDamping: b2Float {
    get {
      return m_gravityScale
    }
    set {
      setAngularDamping(newValue)
    }
  }
  
  /// Set the angular damping of the body.
  public func setAngularDamping(angularDamping: b2Float) {
    m_angularDamping = angularDamping
  }
  
  /// Get the gravity scale of the body.
  public var gravityScale: b2Float {
    get {
      return m_gravityScale
    }
    set {
      setGravityScale(newValue)
    }
  }
  
  /// Set the gravity scale of the body.
  public func setGravityScale(scale: b2Float) {
    m_gravityScale = scale
  }
  
  /// Set the type of this body. This may alter the mass and velocity.
  public func setType(type: b2BodyType) {
    assert(m_world.isLocked == false)
    if m_world.isLocked == true {
      return
    }
      
    if m_type == type {
      return
    }
      
    m_type = type
      
    resetMassData()
      
    if m_type == b2BodyType.staticBody {
      m_linearVelocity.setZero()
      m_angularVelocity = 0.0
      m_sweep.a0 = m_sweep.a
      m_sweep.c0 = m_sweep.c
      synchronizeFixtures()
    }
      
    setAwake(true)
      
    m_force.setZero()
    m_torque = 0.0
      
    // Delete the attached contacts.
    var ce: b2ContactEdge? = m_contactList
    while ce != nil {
      let ce0 = ce!
      ce = ce!.next
      m_world.m_contactManager.destroy(ce0.contact)
    }
    m_contactList = nil
      
    // Touch the proxies so that new contacts will be created (when appropriate)
    let broadPhase = m_world.m_contactManager.m_broadPhase
    for (var f: b2Fixture? = m_fixtureList; f != nil; f = f!.m_next) {
      let proxyCount = f!.m_proxyCount
      for i in 0 ..< proxyCount {
        broadPhase.touchProxy(f!.m_proxies[i].proxyId)
      }
    }
  }
  
  /// Get the type of this body.
  public var type: b2BodyType {
    get {
      return m_type
    }
    set {
      setType(newValue)
    }
  }
  
  /// Should this body be treated like a bullet for continuous collision detection?
  public func setBullet(flag: Bool) {
    if flag {
      m_flags |= Flags.e_bulletFlag
    }
    else {
      m_flags &= ~Flags.e_bulletFlag
    }
  }
  
  /// Is this body treated like a bullet for continuous collision detection?
  public var isBullet: Bool {
    get {
      return (m_flags & Flags.e_bulletFlag) == Flags.e_bulletFlag
    }
    set {
      setBullet(newValue)
    }
  }
  
  /// You can disable sleeping on this body. If you disable sleeping, the
  /// body will be woken.
  public func setSleepingAllowed(flag: Bool) {
    if flag {
      m_flags |= Flags.e_autoSleepFlag
    }
    else {
      m_flags &= ~Flags.e_autoSleepFlag
      setAwake(true)
    }
  }
  
  /// Is this body allowed to sleep
  public var isSleepingAllowed: Bool {
    get {
      return (m_flags & Flags.e_autoSleepFlag) == Flags.e_autoSleepFlag
    }
    set {
      setSleepingAllowed(newValue)
    }
  }
  
  /**
  Set the sleep state of the body. A sleeping body has very
  low CPU cost.

  :param: flag set to true to wake the body, false to put it to sleep.
  */
  public func setAwake(flag: Bool) {
    if flag {
      if (m_flags & Flags.e_awakeFlag) == 0 {
        m_flags |= Flags.e_awakeFlag
        m_sleepTime = 0.0
      }
    }
    else {
      m_flags &= ~Flags.e_awakeFlag
      m_sleepTime = 0.0
      m_linearVelocity.setZero()
      m_angularVelocity = 0.0
      m_force.setZero()
      m_torque = 0.0
    }
  }
  
  /// Get the sleeping state of this body.
  /// @return true if the body is awake.
  public var isAwake: Bool {
    return (m_flags & Flags.e_awakeFlag) == Flags.e_awakeFlag
  }
  
  /// Set the active state of the body. An inactive body is not
  /// simulated and cannot be collided with or woken up.
  /// If you pass a flag of true, all fixtures will be added to the
  /// broad-phase.
  /// If you pass a flag of false, all fixtures will be removed from
  /// the broad-phase and all contacts will be destroyed.
  /// Fixtures and joints are otherwise unaffected. You may continue
  /// to create/destroy fixtures and joints on inactive bodies.
  /// Fixtures on an inactive body are implicitly inactive and will
  /// not participate in collisions, ray-casts, or queries.
  /// Joints connected to an inactive body are implicitly inactive.
  /// An inactive body is still owned by a b2World object and remains
  /// in the body list.
  public func setActive(flag: Bool) {
    assert(m_world.isLocked == false)
      
    if flag == isActive {
      return
    }
      
    if flag {
      m_flags |= Flags.e_activeFlag
      
      // Create all proxies.
      let broadPhase = m_world.m_contactManager.m_broadPhase
      for (var f: b2Fixture? = m_fixtureList; f != nil; f = f!.m_next) {
        f!.createProxies(broadPhase, xf: m_xf)
      }
      
      // Contacts are created the next time step.
    }
    else {
      m_flags &= ~Flags.e_activeFlag
      
      // Destroy all proxies.
      let broadPhase = m_world.m_contactManager.m_broadPhase
      for (var f: b2Fixture? = m_fixtureList; f != nil; f = f!.m_next) {
        f!.destroyProxies(broadPhase)
      }
      
      // Destroy the attached contacts.
      var ce = m_contactList
      while ce != nil {
        let ce0 = ce!
        ce = ce!.next
        m_world.m_contactManager.destroy(ce0.contact)
      }
      m_contactList = nil
    }
  }
  
  /// Get the active state of the body.
  public var isActive: Bool {
    return (m_flags & Flags.e_activeFlag) == Flags.e_activeFlag
  }
  
  /// Set this body to have fixed rotation. This causes the mass
  /// to be reset.
  public func setFixedRotation(flag : Bool) {
    let status = (m_flags & Flags.e_fixedRotationFlag) == Flags.e_fixedRotationFlag
    if status == flag {
      return
    }
        
    if flag {
      m_flags |= Flags.e_fixedRotationFlag
    }
    else {
      m_flags &= ~Flags.e_fixedRotationFlag
    }
        
    m_angularVelocity = 0.0
       
    resetMassData()
  }
  
  /// Does this body have fixed rotation?
  public var isFixedRotation: Bool {
    return (m_flags & Flags.e_fixedRotationFlag) == Flags.e_fixedRotationFlag
  }
  
  /// Get the list of all fixtures attached to this body.
  public func getFixtureList() -> b2Fixture? {
    return m_fixtureList
  }
  
  /// Get the list of all joints attached to this body.
  public func getJointList() -> b2JointEdge? {
    return m_jointList
  }
  
  /// Get the list of all contacts attached to this body.
  /// @warning this list changes during the time step and you may
  /// miss some collisions if you don't use b2ContactListener.
  public func getContactList() -> b2ContactEdge? {
    return m_contactList
  }
  
  /// Get the next body in the world's body list.
  public func getNext() -> b2Body? {
    return m_next
  }
  
  /// Get the user data pointer that was provided in the body definition.
  public var userData: AnyObject? {
    get {
      return m_userData
    }
    set {
      setUserData(newValue)
    }
  }
  
  /// Set the user data. Use this to store your application specific data.
  public func setUserData(data: AnyObject?) {
    m_userData = data
  }
  
  /// Get the parent world of this body.
  public var world: b2World? {
    return m_world
  }
  
  /// Dump this body to a log file
  public func dump() {
    let bodyIndex = m_islandIndex
    
    println("{")
    println("  b2BodyDef bd;")
    println("  bd.type = b2BodyType(\(m_type));")
    println("  bd.position.set(\(m_xf.p.x), \(m_xf.p.y));")
    println("  bd.angle = \(m_sweep.a)")
    println("  bd.linearVelocity.set(\(m_linearVelocity.x), \(m_linearVelocity.y));")
    println("  bd.angularVelocity = \(m_angularVelocity);")
    println("  bd.linearDamping = \(m_linearDamping);")
    println("  bd.angularDamping = \(m_angularDamping);")
    println("  bd.allowSleep = bool(\(m_flags & Flags.e_autoSleepFlag));")
    println("  bd.awake = bool(\(m_flags & Flags.e_awakeFlag));")
    println("  bd.fixedRotation = bool(\(m_flags & Flags.e_fixedRotationFlag));")
    println("  bd.bullet = bool(\(m_flags & Flags.e_bulletFlag));")
    println("  bd.active = bool(\(m_flags & Flags.e_activeFlag));")
    println("  bd.gravityScale = \(m_gravityScale);")
    println("  bodies[\(m_islandIndex)] = m_world->createBody(&bd);")
    println("")
    for (var f = m_fixtureList; f != nil; f = f!.m_next) {
      println("  {")
      f!.dump(bodyIndex)
      println("  }")
    }
    println("}")
  }
  
  public var description: String {
    return "b2Body[type=\(m_type), flags=\(m_flags), xf=\(m_xf), linearVelocity=\(m_linearVelocity), angularVelocity=\(m_angularVelocity), force=\(m_force), torque=\(m_torque), mass=\(m_mass), I=\(m_I), linearDamping=\(m_linearDamping), angularDamping=\(m_angularDamping)]"
  }
  
  // MARK: private methods
  struct Flags {
    static let e_islandFlag		      = UInt16(0x0001)
    static let e_awakeFlag			    = UInt16(0x0002)
    static let e_autoSleepFlag		  = UInt16(0x0004)
    static let e_bulletFlag		      = UInt16(0x0008)
    static let e_fixedRotationFlag	= UInt16(0x0010)
    static let e_activeFlag		      = UInt16(0x0020)
    static let e_toiFlag			      = UInt16(0x0040)
  }
  
  init(_ def: b2BodyDef, _ world: b2World) {
    assert(def.position.isValid())
    assert(def.linearVelocity.isValid())
    assert(b2IsValid(def.angle))
    assert(b2IsValid(def.angularVelocity))
    assert(b2IsValid(def.angularDamping) && def.angularDamping >= 0.0)
    assert(b2IsValid(def.linearDamping) && def.linearDamping >= 0.0)
      
    m_flags = 0
      
    if def.bullet {
      m_flags |= Flags.e_bulletFlag
    }
    if def.fixedRotation {
      m_flags |= Flags.e_fixedRotationFlag
    }
    if def.allowSleep {
      m_flags |= Flags.e_autoSleepFlag
    }
    if def.awake {
      m_flags |= Flags.e_awakeFlag
    }
    if def.active {
      m_flags |= Flags.e_activeFlag
    }
      
    m_world = world
    
    m_xf = b2Transform()
    m_xf.p = def.position
    m_xf.q.set(def.angle)
      
    m_sweep = b2Sweep()
    m_sweep.localCenter = b2Vec2(0.0, 0.0)
    m_sweep.c0 = m_xf.p
    m_sweep.c = m_xf.p
    m_sweep.a0 = def.angle
    m_sweep.a = def.angle
    m_sweep.alpha0 = 0.0
      
//    m_jointList = nil
//    m_contactList = nil
    m_prev = nil
    m_next = nil
      
    m_linearVelocity = def.linearVelocity
    m_angularVelocity = def.angularVelocity
      
    m_linearDamping = def.linearDamping
    m_angularDamping = def.angularDamping
    m_gravityScale = def.gravityScale
      
    m_force = b2Vec2(0.0, 0.0)
    m_torque = 0.0
      
    m_sleepTime = 0.0
      
    m_type = def.type
      
    if m_type == b2BodyType.dynamicBody {
      m_mass = 1.0
      m_invMass = 1.0
    }
    else {
      m_mass = 0.0
      m_invMass = 0.0
    }
      
    m_I = 0.0
    m_invI = 0.0
      
    m_userData = def.userData
      
    m_fixtureList = nil
    m_fixtureCount = 0
  }
  deinit {
  }
  
  func synchronizeFixtures() {
    var xf1 = b2Transform()
    xf1.q.set(m_sweep.a0)
    xf1.p = m_sweep.c0 - b2Mul(xf1.q, m_sweep.localCenter)
      
    let broadPhase = m_world.m_contactManager.m_broadPhase
    for (var f: b2Fixture? = m_fixtureList; f != nil; f = f!.m_next) {
      f!.synchronize(broadPhase, xf1, m_xf)
    }
  }
  func synchronizeTransform() {
    m_xf.q.set(m_sweep.a)
    m_xf.p = m_sweep.c - b2Mul(m_xf.q, m_sweep.localCenter)
  }
  
  // This is used to prevent connected bodies from colliding.
  // It may lie, depending on the collideConnected flag.
  func shouldCollide(other: b2Body) -> Bool {
    // At least one body should be dynamic.
    if m_type != b2BodyType.dynamicBody && other.m_type != b2BodyType.dynamicBody {
      return false
    }
      
    // Does a joint prevent collision?
    for (var jn: b2JointEdge? = m_jointList; jn != nil; jn = jn!.next) {
      if jn!.other === other {
        if jn!.joint.m_collideConnected == false {
				  return false
        }
      }
    }
      
    return true
  }
  
  func advance(alpha: b2Float) {
    // Advance to the new safe time. This doesn't sync the broad-phase.
    m_sweep.advance(alpha: alpha)
    m_sweep.c = m_sweep.c0
    m_sweep.a = m_sweep.a0
    m_xf.q.set(m_sweep.a)
    m_xf.p = m_sweep.c - b2Mul(m_xf.q, m_sweep.localCenter)
  }
  
  // MARK: private variables
  
  var m_type: b2BodyType
  
  var m_flags: UInt16 = 0
  
  var m_islandIndex = 0
  
  var m_xf: b2Transform		// the body origin transform
  var m_sweep: b2Sweep 		// the swept motion for CCD
  
  var m_linearVelocity: b2Vec2
  var m_angularVelocity: b2Float
  
  var m_force: b2Vec2
  var m_torque: b2Float
  
  unowned var m_world: b2World // ** parent **
  var m_prev: b2Body? = nil // ** linked list **
  var m_next: b2Body? = nil // ** linked list **
  
  var m_fixtureList: b2Fixture? = nil // ** owner **
  var m_fixtureCount: Int = 0
  
  var m_jointList: b2JointEdge? = nil // ** reference **
  var m_contactList: b2ContactEdge? = nil // ** reference **
  
  var m_mass: b2Float, m_invMass: b2Float
  
  // Rotational inertia about the center of mass.
  var m_I: b2Float, m_invI: b2Float
  
  var m_linearDamping: b2Float
  var m_angularDamping: b2Float
  var m_gravityScale: b2Float
  
  var m_sleepTime: b2Float
  
  var m_userData: AnyObject?
}