# Standard part ids

A starting list. Add to it, drop what the car doesn't have, and split or merge entries to match how the parts are actually sold for that model. `pos` shows which position suffixes apply. **V** means the part is usually visible on an exterior model (`visible: true`). **OEM only** means a new aftermarket part usually isn't sold, so set `aftermarket: null` with a reason.

## body
| id | pos | V | notes |
|---|---|---|---|
| body_hood | | V | CAPA aftermarket common |
| body_roof | | V | OEM only (roof skin) |
| body_trunk_lid / body_liftgate / body_tailgate | | V | pick the one the body style has |
| body_bumper_front, body_bumper_rear | | V | price the cover; reinforcement bars are separate entries if needed |
| body_bumper_reinforcement_front / _rear | | | hidden behind covers |
| body_grille | | V | |
| body_fender | lh rh | V | |
| body_door_front, body_door_rear | lh rh | V | door shell; mirrors, handles and glass are separate |
| body_quarter_panel | lh rh | V | welded-in; aftermarket exists for many models |
| body_rocker_panel | lh rh | V | |
| body_mirror | lh rh | V | complete assembly; heated/signal versions change price |
| body_door_handle_front, body_door_handle_rear | lh rh | V | |
| body_fuel_door | | V | |

## glass
| id | pos | V | notes |
|---|---|---|---|
| glass_windshield | | V | ADAS camera brackets raise price; record in fitment_note |
| glass_back_window | | V | |
| glass_door_front, glass_door_rear | lh rh | V | |
| glass_quarter | lh rh | V | |
| glass_sunroof | | V | |

## lighting
| id | pos | V | notes |
|---|---|---|---|
| lighting_headlamp | lh rh | V | halogen / LED / HID differ a lot |
| lighting_taillamp | lh rh | V | split tail lamps: add `_inner` / `_outer` |
| lighting_fog_lamp | lh rh | V | |
| lighting_third_brake_lamp | | V | |
| lighting_side_marker | lh rh | V | |

## wheels
| id | pos | V | notes |
|---|---|---|---|
| wheels_wheel | fl fr rl rr | V | |
| wheels_tire | fl fr rl rr | V | record size in name, e.g. "Tire 215/55R17" |
| wheels_spare | | | |

## brakes
| id | pos | V | notes |
|---|---|---|---|
| brakes_rotor | fl fr rl rr | V | often visible through wheel spokes |
| brakes_caliper | fl fr rl rr | V | remanufactured is common |
| brakes_pad_set_front, brakes_pad_set_rear | | | sold per axle |

## suspension / steering
| id | pos | V | notes |
|---|---|---|---|
| suspension_strut_front | lh rh | | |
| suspension_shock_rear | lh rh | | |
| suspension_control_arm_lower_front | lh rh | | |
| steering_rack | | | remanufactured common |
| steering_tie_rod_end | lh rh | | |

## engine / drivetrain / exhaust / cooling / fuel
| id | pos | V | notes |
|---|---|---|---|
| engine_block | | | long block; remanufactured or used, rarely new aftermarket |
| engine_alternator | | | |
| engine_starter | | | |
| drivetrain_transmission | | | remanufactured |
| drivetrain_axle_front | lh rh | | CV axle |
| exhaust_catalytic_converter | | | emissions rules (e.g. CARB) restrict aftermarket by state |
| exhaust_muffler | | V | tip visible |
| cooling_radiator | | | |
| cooling_condenser | | | AC condenser; behind grille |
| fuel_pump | | | |

## electrical / hvac / interior / trim
| id | pos | V | notes |
|---|---|---|---|
| electrical_battery | | | |
| electrical_ecu | | | OEM only; programming needed |
| hvac_compressor | | | |
| interior_seat_front | lh rh | | for cabin models |
| interior_dashboard | | | |
| interior_airbag_driver, interior_airbag_passenger | | | OEM only (safety) |
| trim_badge_rear | | V | |
| trim_molding_door | lh rh | V | |
| trim_wiper_arm | lh rh | V | |
