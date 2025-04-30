;; fleetmint-core.clar
;; FleetMint Vehicle Management System - Core Contract
;;
;; This contract manages vehicle NFTs, driver authorizations, and fleet operations
;; for the FleetMint decentralized vehicle fleet management system. It provides functionality
;; for registering vehicles as NFTs, managing driver permissions, tracking maintenance,
;; recording usage, and enforcing fleet policies.

;; =========================================
;; Constants and Error Codes
;; =========================================

(define-constant contract-owner tx-sender)

;; Error codes
(define-constant err-owner-only (err u100))
(define-constant err-admin-only (err u101))
(define-constant err-maintenance-personnel-only (err u102))
(define-constant err-driver-only (err u103))
(define-constant err-unauthorized (err u104))
(define-constant err-already-registered (err u105))
(define-constant err-not-found (err u106))
(define-constant err-invalid-status (err u107))
(define-constant err-vehicle-in-use (err u108))
(define-constant err-maintenance-required (err u109))
(define-constant err-insufficient-budget (err u110))
(define-constant err-authorization-expired (err u111))
(define-constant err-invalid-input (err u112))

;; Vehicle status codes
(define-constant status-available u1)
(define-constant status-assigned u2)
(define-constant status-maintenance u3)
(define-constant status-out-of-service u4)

;; Role codes
(define-constant role-admin u1)
(define-constant role-maintenance u2)
(define-constant role-driver u3)

;; =========================================
;; Data Maps and Variables
;; =========================================

;; Vehicle registry - stores all registered vehicles and their details
(define-map vehicles 
  { vehicle-id: uint }
  {
    make: (string-ascii 30),
    model: (string-ascii 30),
    year: uint,
    vin: (string-ascii 17),
    status: uint,
    mileage: uint,
    next-maintenance: uint,
    fuel-budget: uint,
    registration-date: uint,
    last-updated: uint
  }
)

;; User roles and permissions
(define-map user-roles
  { user: principal }
  { role: uint }
)

;; Driver authorizations for specific vehicles
(define-map driver-authorizations
  { driver: principal, vehicle-id: uint }
  {
    start-time: uint,
    end-time: uint,
    authorized-by: principal,
    usage-limit: uint,
    current-usage: uint
  }
)

;; Vehicle maintenance records
(define-map maintenance-records
  { vehicle-id: uint, record-id: uint }
  {
    maintenance-type: (string-ascii 50),
    performed-by: principal,
    timestamp: uint,
    mileage: uint,
    cost: uint,
    notes: (string-utf8 200)
  }
)

;; Vehicle usage events
(define-map usage-records
  { vehicle-id: uint, record-id: uint }
  {
    driver: principal,
    start-time: uint,
    end-time: uint,
    start-mileage: uint,
    end-mileage: uint,
    fuel-used: uint,
    purpose: (string-utf8 100)
  }
)

;; Accident/incident reports
(define-map incident-reports
  { vehicle-id: uint, report-id: uint }
  {
    reporter: principal,
    timestamp: uint,
    location: (string-utf8 100),
    description: (string-utf8 200),
    severity: uint,
    status: (string-ascii 20)
  }
)

;; Vehicle-specific counters for generating unique IDs
(define-map vehicle-counters
  { vehicle-id: uint }
  {
    maintenance-counter: uint,
    usage-counter: uint,
    incident-counter: uint
  }
)

;; Global counter for vehicle IDs
(define-data-var next-vehicle-id uint u1)

;; =========================================
;; Private Functions
;; =========================================

;; Check if caller is the contract owner
(define-private (is-owner)
  (is-eq tx-sender contract-owner)
)

;; Check if caller has admin role
(define-private (is-admin)
  (let ((role-data (default-to { role: u0 } (map-get? user-roles { user: tx-sender }))))
    (is-eq (get role role-data) role-admin)
  )
)

;; Check if caller has maintenance personnel role
(define-private (is-maintenance-personnel)
  (let ((role-data (default-to { role: u0 } (map-get? user-roles { user: tx-sender }))))
    (is-eq (get role role-data) role-maintenance)
  )
)

;; Check if caller is authorized for a specific vehicle
(define-private (is-authorized-for-vehicle (vehicle-id uint))
  (let (
    (auth-data (map-get? driver-authorizations { driver: tx-sender, vehicle-id: vehicle-id }))
    (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
  )
    (and
      (is-some auth-data)
      (let ((auth (unwrap-panic auth-data)))
        (and
          (<= (get start-time auth) current-time)
          (> (get end-time auth) current-time)
        )
      )
    )
  )
)

;; Get a vehicle if it exists
(define-private (get-vehicle (vehicle-id uint))
  (map-get? vehicles { vehicle-id: vehicle-id })
)

;; Initialize vehicle counters for a new vehicle
(define-private (init-vehicle-counters (vehicle-id uint))
  (map-set vehicle-counters
    { vehicle-id: vehicle-id }
    {
      maintenance-counter: u0,
      usage-counter: u0,
      incident-counter: u0
    }
  )
)

;; Get and increment a counter
(define-private (get-and-increment-counter (vehicle-id uint) (counter-name (string-ascii 20)))
  (let (
    (counters (default-to 
      { maintenance-counter: u0, usage-counter: u0, incident-counter: u0 }
      (map-get? vehicle-counters { vehicle-id: vehicle-id })))
    (current-value 
      (if (is-eq counter-name "maintenance")
        (get maintenance-counter counters)
        (if (is-eq counter-name "usage")
          (get usage-counter counters)
          (get incident-counter counters))))
    (new-value (+ current-value u1))
  )
    ;; Update the appropriate counter
    (map-set vehicle-counters
      { vehicle-id: vehicle-id }
      (if (is-eq counter-name "maintenance")
        (merge counters { maintenance-counter: new-value })
        (if (is-eq counter-name "usage")
          (merge counters { usage-counter: new-value })
          (merge counters { incident-counter: new-value })))
    )
    current-value  ;; Return the current (pre-increment) value
  )
)

;; Get current timestamp
(define-private (get-current-time)
  (default-to u0 (get-block-info? time (- block-height u1)))
)

;; =========================================
;; Read-Only Functions
;; =========================================

;; Check if a vehicle exists
(define-read-only (vehicle-exists (vehicle-id uint))
  (is-some (get-vehicle vehicle-id))
)

;; Get vehicle details
(define-read-only (get-vehicle-details (vehicle-id uint))
  (let ((vehicle (get-vehicle vehicle-id)))
    (if (is-some vehicle)
      (ok (unwrap-panic vehicle))
      err-not-found
    )
  )
)

;; Check if a principal has a specific role
(define-read-only (has-role (user principal) (role-code uint))
  (let ((role-data (default-to { role: u0 } (map-get? user-roles { user: user }))))
    (is-eq (get role role-data) role-code)
  )
)

;; Check driver authorization for a vehicle
(define-read-only (check-driver-authorization (driver principal) (vehicle-id uint))
  (let (
    (auth-data (map-get? driver-authorizations { driver: driver, vehicle-id: vehicle-id }))
    (current-time (get-current-time))
  )
    (if (is-some auth-data)
      (let ((auth (unwrap-panic auth-data)))
        (if (and
              (<= (get start-time auth) current-time)
              (> (get end-time auth) current-time)
            )
          (ok true)
          (ok false)
        )
      )
      (ok false)
    )
  )
)

;; Get maintenance records for a vehicle
(define-read-only (get-maintenance-record (vehicle-id uint) (record-id uint))
  (map-get? maintenance-records { vehicle-id: vehicle-id, record-id: record-id })
)

;; Get usage record for a vehicle
(define-read-only (get-usage-record (vehicle-id uint) (record-id uint))
  (map-get? usage-records { vehicle-id: vehicle-id, record-id: record-id })
)

;; Get incident report for a vehicle
(define-read-only (get-incident-report (vehicle-id uint) (report-id uint))
  (map-get? incident-reports { vehicle-id: vehicle-id, report-id: report-id })
)

;; Check if vehicle needs maintenance
(define-read-only (needs-maintenance (vehicle-id uint))
  (let ((vehicle (get-vehicle vehicle-id)))
    (if (is-some vehicle)
      (let ((v (unwrap-panic vehicle)))
        (> (get mileage v) (get next-maintenance v))
      )
      false
    )
  )
)

;; =========================================
;; Public Functions
;; =========================================

;; Register a new vehicle
(define-public (register-vehicle 
  (make (string-ascii 30)) 
  (model (string-ascii 30)) 
  (year uint) 
  (vin (string-ascii 17))
  (initial-mileage uint)
  (maintenance-interval uint)
  (fuel-budget uint)
)
  (let (
    (vehicle-id (var-get next-vehicle-id))
    (current-time (get-current-time))
  )
    ;; Only admins can register vehicles
    (asserts! (or (is-owner) (is-admin)) err-admin-only)
    
    ;; Basic validation
    (asserts! (> (len make) u0) err-invalid-input)
    (asserts! (> (len model) u0) err-invalid-input)
    (asserts! (> year u1900) err-invalid-input)
    (asserts! (is-eq (len vin) u17) err-invalid-input)
    
    ;; Register the vehicle
    (map-set vehicles
      { vehicle-id: vehicle-id }
      {
        make: make,
        model: model,
        year: year,
        vin: vin,
        status: status-available,
        mileage: initial-mileage,
        next-maintenance: (+ initial-mileage maintenance-interval),
        fuel-budget: fuel-budget,
        registration-date: current-time,
        last-updated: current-time
      }
    )
    
    ;; Initialize counters for the new vehicle
    (init-vehicle-counters vehicle-id)
    
    ;; Increment the vehicle ID counter
    (var-set next-vehicle-id (+ vehicle-id u1))
    
    (ok vehicle-id)
  )
)

;; Update vehicle status
(define-public (update-vehicle-status (vehicle-id uint) (new-status uint))
  (let ((vehicle (get-vehicle vehicle-id)))
    ;; Check permissions and vehicle existence
    (asserts! (or (is-owner) (is-admin) (is-maintenance-personnel)) err-unauthorized)
    (asserts! (is-some vehicle) err-not-found)
    (asserts! (or 
              (is-eq new-status status-available)
              (is-eq new-status status-assigned)
              (is-eq new-status status-maintenance)
              (is-eq new-status status-out-of-service)
             ) err-invalid-status)
    
    ;; Update the vehicle status
    (map-set vehicles
      { vehicle-id: vehicle-id }
      (merge (unwrap-panic vehicle)
        { 
          status: new-status,
          last-updated: (get-current-time)
        }
      )
    )
    
    (ok true)
  )
)

;; Assign a role to a user
(define-public (assign-role (user principal) (role-code uint))
  (begin
    ;; Only owner or admin can assign roles
    (asserts! (or (is-owner) (is-admin)) err-admin-only)
    
    ;; Validate role code
    (asserts! (or 
              (is-eq role-code role-admin)
              (is-eq role-code role-maintenance)
              (is-eq role-code role-driver)
             ) err-invalid-input)
    
    ;; Set the user's role
    (map-set user-roles
      { user: user }
      { role: role-code }
    )
    
    (ok true)
  )
)

;; Authorize a driver for a vehicle
(define-public (authorize-driver 
  (driver principal) 
  (vehicle-id uint) 
  (start-time uint) 
  (end-time uint)
  (usage-limit uint)
)
  (let ((vehicle (get-vehicle vehicle-id)))
    ;; Check permissions and vehicle existence
    (asserts! (or (is-owner) (is-admin)) err-admin-only)
    (asserts! (is-some vehicle) err-not-found)
    (asserts! (>= end-time start-time) err-invalid-input)
    
    ;; Create the authorization
    (map-set driver-authorizations
      { driver: driver, vehicle-id: vehicle-id }
      {
        start-time: start-time,
        end-time: end-time,
        authorized-by: tx-sender,
        usage-limit: usage-limit,
        current-usage: u0
      }
    )
    
    ;; If the vehicle is available, change status to assigned
    (if (is-eq (get status (unwrap-panic vehicle)) status-available)
      (map-set vehicles
        { vehicle-id: vehicle-id }
        (merge (unwrap-panic vehicle)
          { 
            status: status-assigned,
            last-updated: (get-current-time)
          }
        )
      )
      true
    )
    
    (ok true)
  )
)

;; Record vehicle maintenance
(define-public (record-maintenance 
  (vehicle-id uint) 
  (maintenance-type (string-ascii 50)) 
  (mileage uint) 
  (cost uint)
  (notes (string-utf8 200))
)
  (let (
    (vehicle (get-vehicle vehicle-id))
    (record-id (get-and-increment-counter vehicle-id "maintenance"))
  )
    ;; Check permissions and vehicle existence
    (asserts! (or (is-owner) (is-admin) (is-maintenance-personnel)) err-unauthorized)
    (asserts! (is-some vehicle) err-not-found)
    
    ;; Record the maintenance
    (map-set maintenance-records
      { vehicle-id: vehicle-id, record-id: record-id }
      {
        maintenance-type: maintenance-type,
        performed-by: tx-sender,
        timestamp: (get-current-time),
        mileage: mileage,
        cost: cost,
        notes: notes
      }
    )
    
    ;; Update vehicle mileage and next maintenance
    (let ((v (unwrap-panic vehicle)))
      (map-set vehicles
        { vehicle-id: vehicle-id }
        (merge v
          { 
            mileage: mileage,
            next-maintenance: (+ mileage (- (get next-maintenance v) (get mileage v))),
            status: status-available,
            last-updated: (get-current-time)
          }
        )
      )
    )
    
    (ok record-id)
  )
)

;; Start vehicle usage
(define-public (start-vehicle-usage (vehicle-id uint) (purpose (string-utf8 100)))
  (let (
    (vehicle (get-vehicle vehicle-id))
    (auth-data (map-get? driver-authorizations { driver: tx-sender, vehicle-id: vehicle-id }))
    (current-time (get-current-time))
    (record-id (get-and-increment-counter vehicle-id "usage"))
  )
    ;; Check vehicle exists and driver is authorized
    (asserts! (is-some vehicle) err-not-found)
    (asserts! (is-some auth-data) err-unauthorized)
    
    (let (
      (v (unwrap-panic vehicle))
      (auth (unwrap-panic auth-data))
    )
      ;; Check authorization validity
      (asserts! (<= (get start-time auth) current-time) err-unauthorized)
      (asserts! (> (get end-time auth) current-time) err-authorization-expired)
      
      ;; Check vehicle status
      (asserts! (is-eq (get status v) status-available) err-vehicle-in-use)
      
      ;; Check maintenance status
      (asserts! (not (needs-maintenance vehicle-id)) err-maintenance-required)
      
      ;; Record usage start
      (map-set usage-records
        { vehicle-id: vehicle-id, record-id: record-id }
        {
          driver: tx-sender,
          start-time: current-time,
          end-time: u0,  ;; Will be updated when usage ends
          start-mileage: (get mileage v),
          end-mileage: u0,  ;; Will be updated when usage ends
          fuel-used: u0,  ;; Will be updated when usage ends
          purpose: purpose
        }
      )
      
      ;; Update vehicle status
      (map-set vehicles
        { vehicle-id: vehicle-id }
        (merge v
          { 
            status: status-assigned,
            last-updated: current-time
          }
        )
      )
      
      (ok record-id)
    )
  )
)

;; End vehicle usage
(define-public (end-vehicle-usage 
  (vehicle-id uint) 
  (record-id uint) 
  (end-mileage uint) 
  (fuel-used uint)
)
  (let (
    (vehicle (get-vehicle vehicle-id))
    (usage-record (map-get? usage-records { vehicle-id: vehicle-id, record-id: record-id }))
    (current-time (get-current-time))
  )
    ;; Check vehicle and record exist
    (asserts! (is-some vehicle) err-not-found)
    (asserts! (is-some usage-record) err-not-found)
    
    (let (
      (v (unwrap-panic vehicle))
      (usage (unwrap-panic usage-record))
    )
      ;; Ensure the caller is the driver who started this usage
      (asserts! (is-eq (get driver usage) tx-sender) err-unauthorized)
      
      ;; Ensure end mileage is greater than start mileage
      (asserts! (> end-mileage (get start-mileage usage)) err-invalid-input)
      
      ;; Update usage record
      (map-set usage-records
        { vehicle-id: vehicle-id, record-id: record-id }
        (merge usage
          {
            end-time: current-time,
            end-mileage: end-mileage,
            fuel-used: fuel-used
          }
        )
      )
      
      ;; Update driver authorization usage counter
      (let ((auth-data (map-get? driver-authorizations { driver: tx-sender, vehicle-id: vehicle-id })))
        (if (is-some auth-data)
          (let ((auth (unwrap-panic auth-data)))
            (map-set driver-authorizations
              { driver: tx-sender, vehicle-id: vehicle-id }
              (merge auth
                { current-usage: (+ (get current-usage auth) (- end-mileage (get start-mileage usage))) }
              )
            )
          )
          true
        )
      )
      
      ;; Update vehicle status and mileage
      (map-set vehicles
        { vehicle-id: vehicle-id }
        (merge v
          { 
            status: status-available,
            mileage: end-mileage,
            fuel-budget: (- (get fuel-budget v) fuel-used),
            last-updated: current-time
          }
        )
      )
      
      (ok true)
    )
  )
)

;; Report an incident
(define-public (report-incident 
  (vehicle-id uint) 
  (location (string-utf8 100)) 
  (description (string-utf8 200))
  (severity uint)
)
  (let (
    (vehicle (get-vehicle vehicle-id))
    (report-id (get-and-increment-counter vehicle-id "incident"))
    (current-time (get-current-time))
  )
    ;; Check vehicle exists
    (asserts! (is-some vehicle) err-not-found)
    
    ;; Check reporter is authorized
    (asserts! (or 
              (is-owner) 
              (is-admin) 
              (is-maintenance-personnel)
              (is-authorized-for-vehicle vehicle-id)
             ) err-unauthorized)
    
    ;; Record the incident
    (map-set incident-reports
      { vehicle-id: vehicle-id, report-id: report-id }
      {
        reporter: tx-sender,
        timestamp: current-time,
        location: location,
        description: description,
        severity: severity,
        status: "reported"
      }
    )
    
    ;; If severity is high (e.g., > 7), mark vehicle as out of service
    (if (> severity u7)
      (map-set vehicles
        { vehicle-id: vehicle-id }
        (merge (unwrap-panic vehicle)
          { 
            status: status-out-of-service,
            last-updated: current-time
          }
        )
      )
      true
    )
    
    (ok report-id)
  )
)

;; Update incident status
(define-public (update-incident-status 
  (vehicle-id uint) 
  (report-id uint) 
  (new-status (string-ascii 20))
)
  (let (
    (report (map-get? incident-reports { vehicle-id: vehicle-id, report-id: report-id }))
  )
    ;; Check permissions and report existence
    (asserts! (or (is-owner) (is-admin) (is-maintenance-personnel)) err-unauthorized)
    (asserts! (is-some report) err-not-found)
    
    ;; Update the report status
    (map-set incident-reports
      { vehicle-id: vehicle-id, report-id: report-id }
      (merge (unwrap-panic report)
        { status: new-status }
      )
    )
    
    (ok true)
  )
)

;; Add fuel budget to a vehicle
(define-public (add-fuel-budget (vehicle-id uint) (amount uint))
  (let ((vehicle (get-vehicle vehicle-id)))
    ;; Check permissions and vehicle existence
    (asserts! (or (is-owner) (is-admin)) err-admin-only)
    (asserts! (is-some vehicle) err-not-found)
    
    ;; Update the fuel budget
    (map-set vehicles
      { vehicle-id: vehicle-id }
      (merge (unwrap-panic vehicle)
        { 
          fuel-budget: (+ (get fuel-budget (unwrap-panic vehicle)) amount),
          last-updated: (get-current-time)
        }
      )
    )
    
    (ok true)
  )
)

;; Decommission a vehicle (remove from service permanently)
(define-public (decommission-vehicle (vehicle-id uint) (reason (string-utf8 200)))
  (let ((vehicle (get-vehicle vehicle-id)))
    ;; Check permissions and vehicle existence
    (asserts! (or (is-owner) (is-admin)) err-admin-only)
    (asserts! (is-some vehicle) err-not-found)
    
    ;; Update vehicle status to out of service
    (map-set vehicles
      { vehicle-id: vehicle-id }
      (merge (unwrap-panic vehicle)
        { 
          status: status-out-of-service,
          last-updated: (get-current-time)
        }
      )
    )
    
    ;; Record as a maintenance event
    (let ((record-id (get-and-increment-counter vehicle-id "maintenance")))
      (map-set maintenance-records
        { vehicle-id: vehicle-id, record-id: record-id }
        {
          maintenance-type: "decommission",
          performed-by: tx-sender,
          timestamp: (get-current-time),
          mileage: (get mileage (unwrap-panic vehicle)),
          cost: u0,
          notes: reason
        }
      )
    )
    
    (ok true)
  )
)