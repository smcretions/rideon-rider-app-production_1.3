import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ride_on/app/route_settings.dart';
import 'package:ride_on/core/utils/theme/project_color.dart';
import 'package:ride_on/core/utils/translate.dart';
import 'package:ride_on/core/extensions/helper/push_notifications.dart';
import 'package:ride_on/core/utils/common_widget.dart' hide goTo;
import 'package:ride_on/core/utils/theme/theme_style.dart';
import 'package:ride_on/domain/entities/Sliders_data.dart';
import 'package:ride_on/domain/entities/catrgory.dart';
import 'package:ride_on/core/extensions/workspace.dart';
import 'package:ride_on/domain/entities/service_type.dart';
import 'package:ride_on/presentation/cubits/slider_cubit.dart';
import 'package:ride_on/presentation/cubits/vehicle_data/get_service_type_cubit.dart';
import 'package:ride_on/presentation/screens/home/parcel_details_screen.dart'
    show ParcelDetailsScreen;
import 'package:ride_on/presentation/widgets/drawer_custom.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/data_store.dart';
import '../../cubits/book_ride_cubit.dart';
import '../../cubits/general_cubit.dart';
import '../../cubits/location/user_current_location_cubit.dart';
import '../../cubits/profile/edit_profile_cubit.dart';
import '../../cubits/realtime/update_ride_request_parameter.dart';
import '../../cubits/vehicle_data/get_vehicle_cetgegory_cubit.dart';
import '../Search/loading_nearby_search_screen.dart';
import '../Search/route_location_screen.dart';

class ItemHomeScreen extends StatefulWidget {
  const ItemHomeScreen({super.key});

  @override
  State<ItemHomeScreen> createState() => _ItemHomeScreenState();
}

class _ItemHomeScreenState extends State<ItemHomeScreen>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<LatLng> _selectedLocation =
      ValueNotifier(const LatLng(0, 0));
  static const LatLng _defaultLocation = LatLng(37.7749, -122.4194);
  Timer? _debounceTimer;
  bool showAlert = false;
  late TabController _tabController;
  int _selectedTab = 0;
  String? pickupLocation;
  String? dropLocation;
  DateTime? selectedDate;
  TimeOfDay? selectedTime;
  double? pickupLat;
  double? pickupLng;
  double? dropLat;
  double? dropLng;
  List<Map<String, dynamic>> scheduledRides = [];

  @override
  void initState() {
    super.initState();
    getFCMToken();

    box.delete('current_parcel_data');
    _tabController = TabController(length: 3, vsync: this, initialIndex: 0);
    _tabController.addListener(_handleTabSelection);
    _loadRecentDropLocations();
    context.read<MyImageCubit>().updateMyImage(myImage);
    context
        .read<BookRideRealTimeDataBaseCubit>()
        .updateUserImageUrl(userImageUrl: myImage);
    context.read<UpdateRideRequestParameterCubit>().updateFirebaseUserParameter(
        rideId: context.read<BookRideRealTimeDataBaseCubit>().state.rideId,
        userParameter: {"userImageUrl": myImage});
    context.read<NameCubit>().updateName(loginModel?.data?.firstName ?? "");
    context.read<EmailCubit>().updateEmail(loginModel?.data?.email ?? "");
    isNumeric = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
      showNotification(context);
    });
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) {
      setState(() {
        _selectedTab = _tabController.index;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Map<String, String>> recentDropLocations = [];
  void _loadRecentDropLocations() {
    final storedList = box.get('recent_drop_locations', defaultValue: []);
    if (storedList is List) {
      recentDropLocations =
          storedList.map((e) => Map<String, String>.from(e)).toList();
    }
    setState(() {});
  }

  String _currentAddress = "";
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isInitialLocationLoaded = false;
  bool _isLoadingLocation = false;

  Future<void> _initializeApp() async {
    // context.read<GetVehicleDataCubit>().getAllCategories();
    context.read<GetServiceTypeDataCubit>().getServiceType();
    context.read<SlidersCubit>().getSlidersList(context);
    getCurrency(context);
    getUserDataLocallyToHandleTheState(context);
    await _loadInitialLocation();
  }

  Future<void> _loadInitialLocation() async {
    if (_isInitialLocationLoaded || _isLoadingLocation) return;
    setState(() => _isLoadingLocation = true);
    final cachedLocation = await _loadCachedLocation();
    if (cachedLocation != null) {
      _selectedLocation.value = cachedLocation;
      setState(() => _isInitialLocationLoaded = true);
    }
    try {
      await startLiveLocationTracking(isInitialLoad: true).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _selectedLocation.value = _defaultLocation;
          setState(() => _isInitialLocationLoaded = true);
        },
      );
    } catch (e) {
      showErrorToastMessage('Error getting location: $e');
      _selectedLocation.value = _defaultLocation;
      setState(() => _isInitialLocationLoaded = true);
    } finally {
      setState(() => _isLoadingLocation = false);
    }
  }

  Future<LatLng?> _loadCachedLocation() async {
    final lat = box.get('last_latitude');
    final lng = box.get('last_longitude');
    if (lat != null && lng != null) {
      return LatLng(lat, lng);
    }
    return null;
  }

  Future<void> startLiveLocationTracking({bool isInitialLoad = false}) async {
    if (_isLoadingLocation && !isInitialLoad) return;
    try {
      _isLoadingLocation = true;
      LocationPermission permission = await _checkPermissions();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (showAlert == true) {
          return;
        }
        _showPermissionDeniedDialog();
        showAlert = true;
        return;
      }
      Position position = await Geolocator.getCurrentPosition(
        // ignore: deprecated_member_use
        desiredAccuracy: LocationAccuracy.high,
      );
      updateUserLocation(position);
    } catch (e) {
      showErrorToastMessage('Error getting location: $e');
    } finally {
      if (!isInitialLoad) {
        _isLoadingLocation = false;
      }
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: notifires.getbgcolor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_on, color: Colors.redAccent, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Location Access Needed".translate(context),
                style: heading2Grey1(context),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "To keep your rides accurate and smooth, please allow location access. You can enable it easily by following these steps:"
                  .translate(context),
              style: regular2(context),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("👉 "),
                Expanded(
                  child: Text("Open your phone's Settings".translate(context),
                      style: regular2(context)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("👉 "),
                Expanded(
                  child: Text("Go to App Permissions".translate(context),
                      style: regular2(context)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("👉 "),
                Expanded(
                  child: Text(
                      "Allow Location Access for this app".translate(context),
                      style: regular2(context)),
                ),
              ],
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "Not Now".translate(context),
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Geolocator.openAppSettings();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.settings, size: 18, color: Colors.white),
            label: Text(
              "Open Settings".translate(context),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<LocationPermission> _checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      showErrorToastMessage(
          // ignore: use_build_context_synchronously
          "Please enable location services".translate(context));
      return LocationPermission.denied;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission;
  }

  void updateUserLocation(Position position) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 1), () {
      context.read<UpdateCurrentAddressCubit>().getAddressFromLatLng(
            latitude: position.latitude,
            longitude: position.longitude,
          );
    });
  }

  void _showParcelDetailsDialog(String maxWeight) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.only(top: 60),
        child: ParcelDetailsScreen(maxWeight: maxWeight),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (v, e) async => dialogExit(context),
      canPop: false,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        drawer: const MyDrawer(),
        key: _scaffoldKey,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(170),
          child: Container(
            color: Colors.transparent,
            child: SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 5),
                  _buildLocationInput(),
                ],
              ),
            ),
          ),
        ),
        body: Container(
          height: double.maxFinite,
          width: double.maxFinite,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.fromARGB(255, 245, 237, 213),
                Color.fromARGB(255, 255, 247, 223),
                Color.fromARGB(255, 248, 242, 226),
                Color.fromARGB(255, 254, 238, 196),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SvgPicture.asset("assets/images/home_group.svg"),
              ),
              SafeArea(
                child: Column(
                  children: [
                    const AutoImageSlider(),
                    const SizedBox(height: 15),
                    _buildTabBar(),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          children: [
                            _buildTabContent(),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        children: [
          BlocBuilder<MyImageCubit, dynamic>(builder: (context, state) {
            return InkWell(
              onTap: () => _scaffoldKey.currentState?.openDrawer(),
              child: myImage.isEmpty
                  ? Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: themeColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        CupertinoIcons.profile_circled,
                        size: 40,
                        color: themeColor,
                      ),
                    )
                  : Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: themeColor, width: 2),
                      ),
                      child: ClipOval(
                        child:
                            myNetworkImage(context.read<MyImageCubit>().state),
                      ),
                    ),
            );
          }),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BlocBuilder<NameCubit, dynamic>(builder: (context, state) {
                  return RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: "Hi, ".translate(context),
                          style: heading2Grey1(context).copyWith(
                            fontSize: 18,
                            color: Colors.grey[700],
                          ),
                        ),
                        TextSpan(
                          text: " ${context.read<NameCubit>().state}",
                          style: heading2Grey1(context).copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: blackColor,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 4),
                Text(
                  "Where do you want to go today?".translate(context),
                  style: heading3Grey1(context).copyWith(
                    color: grey2,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationInput() {
    return BlocBuilder<UpdateCurrentAddressCubit, UpdateCurrentAddressState>(
      builder: (context, state) {
        if (state is UpdateCurrentAddresSuccess) {
          _currentAddress = state.currentAddress ?? '';
          context
              .read<BookRideRealTimeDataBaseCubit>()
              .updatePickupAddress(pickupAddress: _currentAddress);
          context.read<BookRideRealTimeDataBaseCubit>().updatePickupLatAndLng(
                pickupAddressLatitude: state.lat.toString(),
                pickupAddressLongitude: state.lng.toString(),
              );
          context.read<UpdateCurrentAddressCubit>().removeAddress();

          pickupLocation = _currentAddress;
          pickupLat = state.lat;
          pickupLng = state.lng;
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () => _scaffoldKey.currentState?.openDrawer(),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(Icons.menu_outlined, color: themeColor, size: 22),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    context
                        .read<VehicleDataUpdateCubit>()
                        .updateVehicleTypeSelectedId(1);
                    context
                        .read<SelectedAddressCubit>()
                        .pickupAddressController
                        .text = _currentAddress;
                    context
                        .read<GetSuggestionAddressCubit>()
                        .getSuggestions("");

                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UserSearchLocation(
                          currentAddress: _currentAddress,
                        ),
                      ),
                    );
                    _loadRecentDropLocations();
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: themeColor.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.location_on,
                              color: themeColor, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _currentAddress.isEmpty
                                    ? "Fetching location...".translate(context)
                                    : _currentAddress.length > 40
                                        ? "${_currentAddress.substring(0, 40)}..."
                                        : _currentAddress,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: Colors.grey[800],
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios,
                            color: Colors.grey[400], size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<ServiceType> serviceTypes = [];

  bool isLoadingServiceTypes = false;



  Widget _buildTabBar() {
    return BlocBuilder<GetServiceTypeDataCubit, GetServiceTypeDataState>(
      builder: (context, state) {
        bool isLoading = state is GetServiceTypeLoading;

        if (state is GetServiceTypeSuccess) {
          serviceTypes = state.itemTypes;

          if (serviceTypes.isNotEmpty && _selectedTab == 0) {
            context
                .read<GetVehicleDataCubit>()
                .getItemTypesByService(serviceTypes[0].id.toString());
          }
          context.read<GetServiceTypeDataCubit>().resetState();
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            height: 52,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: isLoading
                ? Row(
                    children: [
                      Expanded(child: ShimmerLoader()),
                      const SizedBox(width: 10),
                      Expanded(child: ShimmerLoader()),
                    ],
                  )
                : serviceTypes.isEmpty
                    ? Center(child: Text("No Services".translate(context)))
                    : Row(
                        children: List.generate(serviceTypes.length, (index) {
                          final item = serviceTypes[index];
                          final isSelected = _selectedTab == index;

                          return Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(26),
                              onTap: () {
                                if (_selectedTab == index) return;
                                setState(() {
                                  _selectedTab = index;
                                });

                                context
                                    .read<GetVehicleDataCubit>()
                                    .getItemTypesByService(item.id.toString());
                                context
                                    .read<ServiceTypeId>()
                                    .update(item.id.toString());
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? themeColor
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(26),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  item.name ?? "",
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected ? grey1 : grey2,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
          ),
        );
      },
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 0:
        return _buildRideContent();
      case 1:
        return _buildParcelContent();
      default:
        return _buildRideContent();
    }
  }

  Widget _buildRideContent() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            children: [
              const SizedBox(height: 20),
              if (recentDropLocations.isNotEmpty) _buildRecentSearchesSection(),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "🚗 ${"Choose Your Ride".translate(context)}"
                        .translate(context),
                    style: heading2Grey1(context).copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              BlocBuilder<GetVehicleDataCubit, GetVehicleDataState>(
                  builder: (context, state) {
                List<ItemTypes> itemList = [];
                if (state is GetItemTypeSuccess && state.itemTypes.isNotEmpty) {
                  itemList = state.itemTypes;
                  context
                      .read<SetVehicleCategoryCubit>()
                      .updateSetVehicleCategoryList(itemList);
                }
                bool isLoading = state is GetVehicleLoading;
                return _buildVehicleGrid(itemList, isLoading);
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildParcelContent() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            _buildVehicleSelectionSection(),
            const SizedBox(height: 30),
            _buildDeliveryNotes(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryNotes() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: whiteColor,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(
            color: Colors.green.shade600,
            width: 4,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.note_alt_outlined,
                  color: Colors.green,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "Delivery Notes".translate(context),
                style: heading3Grey1(context).copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "• Ensure proper packaging\n".translate(context) +
                "• Add clear delivery instructions\n".translate(context) +
                "• Include receiver contact info".translate(context),
            style: regular2(context).copyWith(
              fontSize: 12,
              height: 1.6,
              color: Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleSelectionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "🚚 ${"Select Delivery Vehicle".translate(context)}"
                  .translate(context),
              style: heading2Grey1(context).copyWith(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          "Choose the right vehicle for your parcel size".translate(context),
          style: regular2(context).copyWith(
            color: Colors.grey[600],
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 12),
        BlocBuilder<GetVehicleDataCubit, GetVehicleDataState>(
            builder: (context, state) {
          List<ItemTypes> itemList = [];
          if (state is GetItemTypeSuccess && state.itemTypes.isNotEmpty) {
            itemList = state.itemTypes;
            context
                .read<SetVehicleCategoryCubit>()
                .updateSetVehicleCategoryList(itemList);
          }
          bool isLoading = state is GetVehicleLoading;
          return _buildVehicleGrid(itemList, isLoading);
        }),
      ],
    );
  }

  Widget _buildRecentSearchesSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: themeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.history, color: themeColor, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Recent".translate(context),
                    style: heading3Grey1(context).copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (recentDropLocations.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    box.delete('recent_drop_locations');
                    _loadRecentDropLocations();
                  },
                  child: Text(
                    "Clear".translate(context),
                    style: regular2(context).copyWith(
                      color: Colors.redAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (recentDropLocations.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  "No recent searches".translate(context),
                  style: regular2(context).copyWith(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
              ),
            )
          else
            Column(
              children: recentDropLocations.take(2).map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _handleRecentSearchTap(item),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: themeColor.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 32,
                            decoration: BoxDecoration(
                              color: themeColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(Icons.location_on, size: 16, color: themeColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item['address'] ?? "",
                              style: regular(context).copyWith(
                                fontSize: 12.5,
                                color: notifires.getGrey1whiteColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios,
                              size: 12, color: Colors.grey[400]),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  void _handleRecentSearchTap(Map<String, String> item) {
    if (_currentAddress.isEmpty) {
      showAlert = false;
      startLiveLocationTracking();
      setState(() {});
      return;
    }

    context.read<SelectedAddressCubit>().dropOffAddressController.text =
        item['address'] ?? "";
    context.read<BookRideRealTimeDataBaseCubit>().updateDropOffLatAndLng(
          dropoffAddressLatitude: item['lat'] ?? "",
          dropoffAddressLongitude: item['lng'] ?? "",
        );

    final bookRide = context.read<BookRideRealTimeDataBaseCubit>();
    bookRide.updatePickupAddress(pickupAddress: _currentAddress);
    bookRide.updateDropOffAddress(dropoffAddress: item['address'] ?? "");
    box.delete("current_parcel_data");

    if (bookRide.state.pickupAddress.isNotEmpty &&
        bookRide.state.dropoffAddress.isNotEmpty &&
        bookRide.state.pickupAddressLatitude.isNotEmpty &&
        bookRide.state.pickupAddressLongitude.isNotEmpty &&
        bookRide.state.dropoffAddressLatitude.isNotEmpty &&
        bookRide.state.dropoffAddressLongitude.isNotEmpty) {
      goTo(const LoadingNearbySearchScreen());
    }
  }

  Widget _buildVehicleGrid(List<ItemTypes> items, bool isLoading) {
    if (items.isEmpty && !isLoading) {
      return Padding(
        padding: const EdgeInsets.only(top: 50),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.car_repair, color: Colors.grey[300], size: 60),
              const SizedBox(height: 12),
              Text(
                "No vehicles available".translate(context),
                style: regular2(context).copyWith(color: Colors.grey[400]),
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () {
                  context.read<GetServiceTypeDataCubit>().getServiceType();
                  setState(() {
                    _selectedTab = 0;
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: themeColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "Retry".translate(context),
                    style: regular2(context).copyWith(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: isLoading ? 8 : items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemBuilder: (_, index) {
        if (isLoading) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
          );
        }

        final item = items[index];
        return _buildVehicleCard(item);
      },
    );
  }

  Widget _buildVehicleCard(ItemTypes item) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          if (_selectedTab == 0) {
            context
                .read<VehicleDataUpdateCubit>()
                .updateVehicleTypeSelectedId(item.id);
            context.read<SelectedAddressCubit>().pickupAddressController.text =
                _currentAddress;
            context.read<GetSuggestionAddressCubit>().getSuggestions("");
            box.delete('current_parcel_data');

            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => UserSearchLocation(
                  currentAddress: _currentAddress,
                ),
              ),
            );
            _loadRecentDropLocations();
          } else {
            context.read<SelectedAddressCubit>().pickupAddressController.text =
                _currentAddress;
            context.read<GetSuggestionAddressCubit>().getSuggestions("");
            context
                .read<VehicleDataUpdateCubit>()
                .updateVehicleTypeSelectedId(item.id);
            _showParcelDetailsDialog(item.maxWeight ?? "");
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Image.network(
                    item.image ?? "",
                    width: 40,
                    height: 40,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.directions_car,
                      color: themeColor,
                      size: 30,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                item.name ?? "",
                style: heading3(context).copyWith(
                  color: blackColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void getCurrency(BuildContext context) {
  context.read<GeneralCubit>().fetchGeneralSetting(context);
}

class AutoImageSlider extends StatefulWidget {
  const AutoImageSlider({super.key});

  @override
  State<AutoImageSlider> createState() => _AutoImageSliderState();
}

class _AutoImageSliderState extends State<AutoImageSlider> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  Timer? _timer;

  void startAutoSlide(int length) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_currentIndex < length - 1) {
        _currentIndex++;
      } else {
        _currentIndex = 0;
      }

      _pageController.animateToPage(
        _currentIndex,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SlidersCubit, SlidersState>(
      builder: (context, state) {
        if (state is SlidersLoading) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              height: 115,
              child: Shimmer.fromColors(
                baseColor: Colors.grey[300]!,
                highlightColor: Colors.grey[100]!,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
          );
        }

        if (state is SlidersSuccess) {
          List<SliderData> sliders = state.sliderResponse.data ?? [];

          if (sliders.isEmpty) {
            return const SizedBox.shrink();
          }

          startAutoSlide(sliders.length);

          return SizedBox(
            height: 115,
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pageController,
                   itemCount: sliders.length,
                  onPageChanged: (index) {
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    final slider = sliders[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: GestureDetector(
                          onTap: () async {
                            final url = slider.url;
                            if (url != null &&
                                await canLaunchUrl(Uri.parse(url))) {
                              await launchUrl(Uri.parse(url),
                                  mode: LaunchMode.externalApplication);
                            } else {}
                          },
                          child: Image.network(
                            slider.image ?? '',
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Shimmer.fromColors(
                                baseColor: Colors.grey[300]!,
                                highlightColor: Colors.grey[100]!,
                                child: Container(
                                  color: Colors.grey[300],
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) =>
                                const Center(child: Icon(Icons.image)),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // Dots Indicator
                Positioned(
                  bottom: 10,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      sliders.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: _currentIndex == index ? 10 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _currentIndex == index
                              ? Colors.white
                              : Colors.white54,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        if (state is SlidersFailed) {
          return const SizedBox();
        }

        return const SizedBox.shrink();
      },
    );
  }
}
