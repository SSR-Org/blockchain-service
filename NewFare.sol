// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;
import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol';

contract Fare is Ownable {
    address private ride_contract_address;

    struct TAX {
        uint256 cgst;
        uint256 sgst;
    }

    struct CAR_TYPE_PARAMS {
        string car_type_name;
        uint256 minimum_fare;
        uint256 time_multiplier;
        uint256 distance_multiplier;
    }

    struct CITY_PARAMS {
        string city_code;
        uint256 minimum_distance;
        uint256 distance_buffer;
        uint256 time_buffer;
        TAX tax_parameters;
        bool set_car_parameters;
    }

    struct DRIVER_COUNTER_QUOTE {
        address driver;
        uint256 counter_quote_percent;
    }

    struct FARE_SPLIT {
        uint256 cgst;
        uint256 sgst;
        uint256 rider_referrer_amount;
        uint256 driver_referrer_amount;
        uint256 driver_earnings;
        uint256 base_fare_without_tax;
        uint256 premium_fare_without_tax;
    }

    struct RIDE_FARE {
        uint256 ride_id;
        uint256 base_fare;
        uint256 boost_percent;
        uint256 chosen_mileage;
        uint256 estimated_fare;
        uint256 final_fare;
        mapping(address => DRIVER_COUNTER_QUOTE) counter_quotes;
        FARE_SPLIT fare_split_details;
        // bool buffer_check;
    }

    mapping(string => mapping(string => CAR_TYPE_PARAMS)) public city_car_type;
    mapping(string => CITY_PARAMS) public city;
    mapping(uint256 => RIDE_FARE) public ride_fare;

    event Base_Fare(uint256 ride_id, uint256 fare_amount);
    event Estimated_Fare(uint256 ride_id, uint256 fare_amount);
    event Final_Fare(uint256 ride_id, uint256 final_fare);
    event Fare_Split_Details(
        uint256 ride_id,
        uint256 cgst,
        uint256 sgst,
        uint256 rider_referrer_amount,
        uint256 driver_referrer_amount,
        uint256 driver_earnings,
        uint256 base_fare_without_tax,
        uint256 premium_fare_without_tax
    );

    modifier _isRideContract() {
        require(msg.sender == ride_contract_address, 'Invalid Call');
        _;
    }

    modifier _cityExists(string memory city_code) {
        require(
        keccak256(abi.encodePacked(city[city_code].city_code)) ==
            keccak256(abi.encodePacked(city_code)),
        'City doesnot exists'
        );
        _;
    }

    modifier _carTypeExists(string memory city_code, string memory) {
        require(
        keccak256(abi.encodePacked(city[city_code].city_code)) ==
            keccak256(abi.encodePacked(city_code)),
        'City doesnot exists'
        );
        _;
    }

    modifier _driverCounterQuoteExists(address driver, uint256 ride_id) {
        require(
            ride_fare[ride_id].counter_quotes[driver].driver == driver,
            'Driver is not eligible'
        );
        _;
    }

    function setRideContractAddress(address new_ride_contract_address) public {
        ride_contract_address = new_ride_contract_address;
    }

    function setCityParameter(
        string memory city_code,
        uint256 minimum_distance,
        uint256 distance_buffer,
        uint256 time_buffer,
        uint256 cgst,
        uint256 sgst
    ) public onlyOwner {
        TAX memory city_tax = TAX(cgst, sgst);
        CITY_PARAMS storage city_details = city[city_code];
        city_details.city_code = city_code;
        city_details.minimum_distance = minimum_distance;
        city_details.distance_buffer = distance_buffer;
        city_details.time_buffer = time_buffer;
        city_details.tax_parameters = city_tax;
        city_details.set_car_parameters = false;
    }

    function setCityCarTyeParameters(
        string memory city_code,
        string memory car_type_name,
        uint256 minimum_fare,
        uint256 time_multiplier,
        uint256 distance_multiplier
    ) public onlyOwner {
        CAR_TYPE_PARAMS storage ct = city_car_type[city_code][car_type_name];
        ct.car_type_name = car_type_name;
        ct.minimum_fare = minimum_fare;
        ct.time_multiplier = time_multiplier;
        ct.distance_multiplier = distance_multiplier;
    }

    function baseFareCalculation(
        string memory city_code,
        string memory car_type,
        uint256 time,
        uint256 distance
    ) public view _cityExists(city_code) returns (uint256 fare_after_tax) {
        CITY_PARAMS memory city_params = city[city_code];
        CAR_TYPE_PARAMS memory car_params = city_car_type[city_code][car_type];
        TAX memory tax_details = city_params.tax_parameters;
        
        uint256 distance_to_multiply = distance - city_params.minimum_distance;
        uint256 fare_before_tax = car_params.minimum_fare +
        (car_params.time_multiplier * time) +
        (car_params.distance_multiplier * distance_to_multiply) /
        uint256(1000);

        uint256 fare = fare_before_tax < car_params.minimum_fare
        ? car_params.minimum_fare
        : fare_before_tax;

        fare_after_tax =
        (fare * (uint256(10000) + tax_details.cgst + tax_details.sgst)) /
        uint256(10000);
    }

    function calculateEstimatedFare(uint256 fare_amount, uint256 mileage)
        internal
        pure
        returns (uint256 estimatedFare)
    {
        estimatedFare = ((mileage + 10000) * fare_amount) / 10000; 
        return estimatedFare;
    }

    function storeBaseFare(
        uint256 ride_id,
        uint256 distance,
        uint256 time,
        uint256 boost_percent,
        string memory city_code,
        string memory car_type
    ) external _isRideContract _cityExists(city_code) { 
        RIDE_FARE storage new_ride_fare = ride_fare[ride_id];
        new_ride_fare.ride_id = ride_id;
        uint256 base_fare = baseFareCalculation(
        city_code,
        car_type,
        time,
        distance
        );

        new_ride_fare.base_fare = calculateEstimatedFare(base_fare, boost_percent); // boost_precentage as mileage???

        emit Base_Fare(ride_id, base_fare);
    }

    function addCounterQuote(
        uint256 boost_percent,
        uint256 ride_id,
        address driver
    ) external _isRideContract {
        ride_fare[ride_id].counter_quotes[driver] = DRIVER_COUNTER_QUOTE(
        driver,
        boost_percent
        );
    }

    function storeEstimatedFare(uint256 ride_id, address driver)
        public
        _isRideContract
        _driverCounterQuoteExists(driver, ride_id)
    {
        ride_fare[ride_id].chosen_mileage = ride_fare[ride_id]
        .counter_quotes[driver]
        .counter_quote_percent;
        uint256 estimated_fare = calculateEstimatedFare(
        ride_fare[ride_id].base_fare,
        ride_fare[ride_id].counter_quotes[driver].counter_quote_percent
        );
        ride_fare[ride_id].estimated_fare = estimated_fare;
        emit Estimated_Fare(ride_id, estimated_fare);
    }

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
    ) external _isRideContract {
        ride_fare[ride_id].fare_split_details = FARE_SPLIT(
            cgst,
            sgst,
            rider_referrer_amount,
            driver_referrer_amount,
            driver_earnings,
            base_fare_without_tax,
            premium_fare_without_tax
        );
        ride_fare[ride_id].final_fare = final_fare;
        emit Final_Fare(ride_id, final_fare);
        emit Fare_Split_Details(
            ride_id,
            cgst,
            sgst,
            driver_referrer_amount,
            rider_referrer_amount,
            driver_earnings,
            base_fare_without_tax,
            premium_fare_without_tax
        );
    }
}