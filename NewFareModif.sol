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
        uint256 chosen_mileage; //???
        uint256 estimated_fare;
        uint256 final_fare;
        mapping(address => DRIVER_COUNTER_QUOTE) counter_quotes;
        FARE_SPLIT fare_split_details;
        // bool buffer_check; //??
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

    modifier _driverCounterQuoteExists(address driver, uint256 ride_id) {
        require(
            ride_fare[ride_id].counter_quotes[driver].driver == driver,
            'Driver is not eligible'
        );
        _;
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

        // let distance_to_multiply: int = if (distance < state.city_fare_meta[city_code].minimum_distance) state.city_fare_meta[city_code].minimum_distance else distance
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

        bool buffer_check = absDifference(rcs.final_distance, rcs.initial_distance) <
          city_params.distance_buffer &&
          (
            SafeMath.div(
              SafeMath.mul(100, absDifference(rcs.initial_time, rcs.final_time)),
              rcs.initial_time
            )
          ) <
          city_params.time_buffer;
        if (buffer_check) {
          final_fare = ride_fare[ride_id].estimated_fare;
          ride_fare[ride_id].final_fare = final_fare;
        } else {

          uint256 new_base_fare = baseFareCalculation(
              rcs.city_code,
              rcs.car_type,
              rcs.final_time,
              rcs.final_distance
            );
          final_fare = calculateEstimatedFare(
            new_base_fare,
            ride_fare[ride_id].chosen_mileage
          );
          ride_fare[ride_id].final_fare = final_fare;
        }
        ride_fare[ride_id].buffer_check = buffer_check;
        splitRideFare(ride_id, rcs.city_code);
        disburseFare(ride_id, driver, rider);

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