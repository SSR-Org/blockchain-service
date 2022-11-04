// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;
import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol';

interface Fare {
    function storeBaseFare(
        uint256 ride_id,
        uint256 distance,
        uint256 time,
        uint256 boost_percent,
        string memory city_code,
        string memory car_type
    ) external;

    function addCounterQuote(
        uint256 boost_percent,
        uint256 ride_id,
        address driver
    ) external;

    function storeEstimatedFare(uint256 ride_id, address driver) external;

    function storeFinalFare(
        uint256 ride_id,
        uint256 final_fare,
        uint256 cgst,
        uint256 sgst,
        uint256 rider_referrer_amount,
        uint256 driver_referrer_amount,
        uint256 driver_earnings,
        uint256 base_fare_without_tax,
        uint256 premium_fare_without_tax
    ) external;
}

contract Ride is Ownable {
    uint256 private id;
    address fare_contract_address;
    Fare fare_contract;

    struct RIDE_DATA {
        uint256 ride_id;
        uint256 ride_state; // [0,1,2,6,13]
        // 'new-request': 0,
        // 'counter-quoted': 1,
        // 'ride-accepted': 2,
        // 'successfully-completed': 6,
        // 'cancelled-by-rider': 13,
        address rider;
        address driver;
        uint256 initial_distance;
        uint256 initial_time;
        uint256 final_distance;
        uint256 final_time;
        string city_code;
        string car_type;
    }

    mapping(address => bool) public is_rider_processing;
    mapping(address => bool) public is_driver_processing;
    mapping(uint256 => RIDE_DATA) rides; 
    event Ride_Requested(address rider, uint256 ride_id);

    constructor(uint256 start_ride_id, address new_fare_contract_address) {
        id = start_ride_id;
        fare_contract_address = new_fare_contract_address;
        fare_contract = Fare(new_fare_contract_address);
    }

    modifier _isRiderBusy(address rider) {
        require(!currentRiderStatus(rider), 'Rider is in Ride');
        _;
    }

    modifier _isDriverBusy(address driver) {
        require(!currentDriverStatus(driver), 'Driver is in Ride');
        _;
    }

    modifier _rideExists(uint256 ride_id) {
        require(ride_id == rides[ride_id].ride_id, 'Ride Doesnot Exists');
        _;
    }

    modifier _isRider(uint256 ride_id) {
        require(_msgSender() == rides[ride_id].rider, 'User is not Rider');
        _;
    }

    modifier _isDriver(uint256 ride_id) {
        require(_msgSender() == rides[ride_id].driver, 'User is not Driver');
        _;
    }

    function setFareContractAddress(address new_fare_contract_address)
        public
        onlyOwner
    {
        fare_contract_address = new_fare_contract_address;

        fare_contract = Fare(new_fare_contract_address);
    }

    function currentRiderStatus(address rider) internal view returns (bool) {
        return is_rider_processing[rider];
    }

    function currentDriverStatus(address driver) internal view returns (bool) {
        return is_driver_processing[driver];
    }

    function requestRide(
        uint256 initial_distance,
        uint256 initial_time,
        string memory city_code,
        string memory car_type,
        uint256 boost_percent
    ) public _isRiderBusy(msg.sender) returns (uint256) {
        uint256 current_id = getId();
        uint256 new_ride_id = current_id + 1;

        RIDE_DATA storage new_ride = rides[new_ride_id];
        new_ride.ride_id = new_ride_id;
        new_ride.rider = msg.sender;
        new_ride.initial_distance = initial_distance;
        new_ride.initial_time = initial_time;
        new_ride.city_code = city_code;
        new_ride.car_type = car_type;
        new_ride.ride_state = 0;
        is_rider_processing[msg.sender] = true;
        Fare(fare_contract_address).storeBaseFare(
            new_ride_id,
            initial_distance,
            initial_time,
            boost_percent,
            city_code,
            car_type
        );
        incrementId();

        emit Ride_Requested(msg.sender, new_ride_id);
        return new_ride_id;
    }

    function counterQuote(uint256 boost_percent, uint256 ride_id)
        public
        _isDriverBusy(msg.sender)
        _rideExists(ride_id)
    {
        require(rides[ride_id].ride_state == 0, 'Invalid Ride State');
        fare_contract.addCounterQuote(boost_percent, ride_id, msg.sender);
        rides[ride_id].ride_state = 1;
    }

    function acceptRide(uint256 ride_id, address driver)
        public
        _isRider(ride_id)
    {
        rides[ride_id].driver = driver;
        fare_contract.storeEstimatedFare(ride_id, driver); 
        is_driver_processing[_msgSender()] = true;
        rides[ride_id].ride_state = 2;
    }

    function cancelRide(uint256 ride_id) public {
        RIDE_DATA memory ride_details = rides[ride_id];
        rides[ride_id].ride_state = 13;
        is_rider_processing[ride_details.rider] = false;
        is_driver_processing[ride_details.driver] = false;
    }

    function endRide(
        uint256 ride_id,
        uint256 distance,
        uint256 time,
        uint256 final_fare,
        uint256 cgst,
        uint256 sgst,
        uint256 rider_referrer_amount,
        uint256 driver_referrer_amount,
        uint256 driver_earnings,
        uint256 base_fare_without_tax,
        uint256 premium_fare_without_tax
    ) public {
        RIDE_DATA storage ride = rides[ride_id];
        require(ride.driver == _msgSender(), 'User is not a driver');

        ride.final_time = time;
        ride.final_distance = distance;

        fare_contract.storeFinalFare(
            ride_id,
            final_fare,
            cgst,
            sgst,
            rider_referrer_amount,
            driver_referrer_amount,
            driver_earnings,
            base_fare_without_tax,
            premium_fare_without_tax
        );
        is_rider_processing[ride.rider] = false;
        is_driver_processing[ride.driver] = false;

        rides[ride_id].ride_state = 6;
    }

    function incrementId() internal {
        id = id + 1;
    }

    function getId() internal view returns (uint256) {
        return id;
    }

    function getRideDetails(uint256 _ride_id)
        public
        view
        returns (
            uint256 ride_id,
            uint256 ride_state,
            address rider,
            address driver,
            uint256 initial_distance,
            uint256 initial_time,
            uint256 final_distance,
            uint256 final_time,
            string memory city_code,
            string memory car_type
        )
    {
        RIDE_DATA memory ride_data = rides[_ride_id];
        ride_id = ride_data.ride_id;
        ride_state = ride_data.ride_state;
        rider = ride_data.rider;
        driver = ride_data.driver;
        initial_distance = ride_data.initial_distance;
        initial_time = ride_data.initial_time;
        final_distance = ride_data.final_distance;
        final_time = ride_data.final_time;
        city_code = ride_data.city_code;
        car_type = ride_data.car_type;
    }

    function _getRideState(uint256 ride_id)
        internal
        view
        returns (uint256 ride_state)
    {
        ride_state = rides[ride_id].ride_state;
    }
}