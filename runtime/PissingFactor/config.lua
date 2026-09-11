-- Server-owned gameplay settings. Clients cannot override the host's values.
return {
    EnablePrototype = false, -- unfinished integration; use only in a disposable test world
    ReliefSeconds = 8.0,
    RangeCm = 400.0,
    StainSeconds = 60.0,
    StainFadeSeconds = 10.0,
    WaterSeconds = 4.0,
    MaxStains = 256,
    StampsPerSecond = 5,
    InputTimeoutSeconds = 1.0,
    TickSeconds = 0.1,
    Debug = false,
}
