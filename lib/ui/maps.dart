import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_map_polyutil/google_map_polyutil.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movelo/models/arbol.dart';
import 'package:movelo/models/registroGeografico.dart';
import 'dart:math' show cos, sqrt, asin;

import 'package:movelo/blocs/bloc.dart';
import 'package:movelo/providers/estadoGlobal.dart';
import 'package:movelo/ui/widgets/infoCardNoLogo.dart';
import 'package:movelo/ui/widgets/infoCardNumbers.dart';
import 'package:movelo/ui/widgets/infoCardRestantes.dart';
import 'package:provider/provider.dart';
import 'package:rflutter_alert/rflutter_alert.dart';

class Maps extends StatefulWidget {
  @override
  _MapsState createState() => _MapsState();
}

class _MapsState extends State<Maps> {
  CameraPosition _initialLocation = CameraPosition(target: LatLng(0.0, 0.0));
  GoogleMapController mapController;

  final Geolocator _geolocator = Geolocator();

  Position _currentPosition;
  Position _lastPosition;
  Position _destinationPosition;
  String _currentAddress;

  final startAddressController = TextEditingController();
  final destinationAddressController = TextEditingController();

  String _startAddress = '';
  String _destinationAddress = '';
  String _placeDistance = "";
  double _distanciaRecorrida = 0;

  Set<Marker> markers = {};

  PolylinePoints polylinePoints;
  Map<PolylineId, Polyline> polylines = {};
  List<LatLng> polylineCoordinates = [];
  List<LatLng> polylineCoordinates2 = [];
  List<Registro> registrosGeograficos = [];
  Bloc bloc = new Bloc();

  bool _rutaEscogida = false;
  bool _navegarRuta = false;
  bool _puntoInicioView = false;
  bool _huellaCarbono = false;

  List<Arbol> arbolesUsuario = [];

  Timer _timer;

  double containerSize = 130;
  double _pCarro = 0; //Huellas de carbono
  double _pMoto = 0;
  double _pBici = 0;

  EstadoGlobal proveedor;

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  Widget _textField(
      {TextEditingController controller,
      String label,
      String hint,
      String initialValue,
      double width,
      Icon prefixIcon,
      Widget suffixIcon,
      Function(String) locationCallback,
      double multiplier}) {
    return Container(
      width: width * multiplier,
      child: TextField(
        onChanged: (value) {
          locationCallback(value);
        },
        controller: controller,
        // initialValue: initialValue,
        decoration: new InputDecoration(
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(10.0),
            ),
            borderSide: BorderSide(
              color: Colors.grey[400],
              width: 2,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(10.0),
            ),
            borderSide: BorderSide(
              color: Colors.blue[300],
              width: 2,
            ),
          ),
          contentPadding: EdgeInsets.all(15),
          hintText: hint,
        ),
      ),
    );
  }

  // Method for retrieving the current location
  _getCurrentLocation() async {
    await _geolocator
        .getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
        .then((Position position) async {
      setState(() {
        _lastPosition = _currentPosition;
        _currentPosition = position;
        print('Posición actual: $_currentPosition');
        mapController.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(position.latitude, position.longitude),
              zoom: 16.0,
            ),
          ),
        );
      });
      await _getAddress();
    }).catchError((e) {
      print(e);
    });
  }

  // Method for retrieving the address
  _getAddress() async {
    try {
      List<Placemark> p = await _geolocator.placemarkFromCoordinates(
          _currentPosition.latitude, _currentPosition.longitude);

      Placemark place = p[0];

      setState(() {
        _currentAddress =
            "${place.name}, ${place.locality}, ${place.postalCode}, ${place.country}";
        startAddressController.text = _currentAddress;
        _startAddress = _currentAddress;
      });
    } catch (e) {
      print(e);
    }
  }

  // Method for calculating the distance between two places
  Future<bool> _calculateDistance() async {
    try {
      // Retrieving placemarks from addresses
      List<Placemark> startPlacemark =
          await _geolocator.placemarkFromAddress(_startAddress);
      List<Placemark> destinationPlacemark =
          await _geolocator.placemarkFromAddress(_destinationAddress);

      if (startPlacemark != null && destinationPlacemark != null) {
        // Use the retrieved coordinates of the current position,
        // instead of the address if the start position is user's
        // current position, as it results in better accuracy.
        Position startCoordinates = _startAddress == _currentAddress
            ? Position(
                latitude: _currentPosition.latitude,
                longitude: _currentPosition.longitude)
            : startPlacemark[0].position;
        Position destinationCoordinates = destinationPlacemark[0].position;

        // Start Location Marker
        Marker startMarker = Marker(
          markerId: MarkerId('$startCoordinates'),
          position: LatLng(
            startCoordinates.latitude,
            startCoordinates.longitude,
          ),
          infoWindow: InfoWindow(
            title: 'Inicio',
            snippet: _startAddress,
          ),
          icon: BitmapDescriptor.defaultMarker,
        );

        // Destination Location Marker
        Marker destinationMarker = Marker(
          markerId: MarkerId('$destinationCoordinates'),
          position: LatLng(
            destinationCoordinates.latitude,
            destinationCoordinates.longitude,
          ),
          infoWindow: InfoWindow(
            title: 'Destino',
            snippet: _destinationAddress,
          ),
          icon: BitmapDescriptor.defaultMarker,
        );

        // Adding the markers to the list
        markers.add(startMarker);
        markers.add(destinationMarker);

        print('COORDENADAS DE INICIO: $startCoordinates');
        print('COORDENADAS DE FINA $destinationCoordinates');

        Position _northeastCoordinates;
        Position _southwestCoordinates;

        // Calculating to check that
        // southwest coordinate <= northeast coordinate
        if (startCoordinates.latitude <= destinationCoordinates.latitude) {
          _southwestCoordinates = startCoordinates;
          _northeastCoordinates = destinationCoordinates;
        } else {
          _southwestCoordinates = destinationCoordinates;
          _northeastCoordinates = startCoordinates;
        }

        // Accomodate the two locations within the
        // camera view of the map
        mapController.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              northeast: LatLng(
                _northeastCoordinates.latitude,
                _northeastCoordinates.longitude,
              ),
              southwest: LatLng(
                _southwestCoordinates.latitude,
                _southwestCoordinates.longitude,
              ),
            ),
            100.0,
          ),
        );

        // Calculating the distance between the start and the end positions
        // with a straight path, without considering any route
        // double distanceInMeters = await Geolocator().bearingBetween(
        //   startCoordinates.latitude,
        //   startCoordinates.longitude,
        //   destinationCoordinates.latitude,
        //   destinationCoordinates.longitude,
        // );
        _destinationPosition = destinationCoordinates;
        await _createPolylines(startCoordinates, destinationCoordinates);

        double totalDistance = 0.0;

        // Calculating the total distance by adding the distance
        // between small segments
        for (int i = 0; i < polylineCoordinates.length - 1; i++) {
          totalDistance += await _coordinateDistance(
            polylineCoordinates[i].latitude,
            polylineCoordinates[i].longitude,
            polylineCoordinates[i + 1].latitude,
            polylineCoordinates[i + 1].longitude,
          );
          print(polylineCoordinates[i].latitude);
          print(polylineCoordinates[i].longitude);
        }

        setState(() {
          _placeDistance = totalDistance.toStringAsFixed(2);
        });

        return true;
      }
    } catch (e) {
      print(e);
    }
    return false;
  }

  // Formula for calculating distance between two coordinates
  // https://stackoverflow.com/a/54138876/11910277
  Future<double> _coordinateDistance(lat1, lon1, lat2, lon2) async {
    double distance = await _geolocator.distanceBetween(lat1, lon1, lat2, lon2);

    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    //distance = 12742 * asin(sqrt(a));
    return distance / 1000;
  }

  Future avanzarRuta() async {
    _getCurrentLocation();
    bool dentro = await GoogleMapPolyUtil.isLocationOnPath(
        point: LatLng(_currentPosition.latitude, _currentPosition.longitude),
        polygon: polylineCoordinates,
        tolerance: 30);
    double distance = await _geolocator.distanceBetween(
            _currentPosition.latitude,
            _currentPosition.longitude,
            _lastPosition.latitude,
            _lastPosition.longitude) /
        1000;
    if (!dentro) {
      if (polylineCoordinates.isNotEmpty) {
        markers.clear();
        polylineCoordinates.clear();

        Marker destinationMarker = Marker(
          markerId: MarkerId('$_destinationPosition'),
          position: LatLng(
            _destinationPosition.latitude,
            _destinationPosition.longitude,
          ),
          infoWindow: InfoWindow(
            title: 'Destino',
            snippet: _destinationAddress,
          ),
          icon: BitmapDescriptor.defaultMarker,
        );

        // Adding the markers to the list
        markers.add(destinationMarker);
      }
      _createPolylines(_currentPosition, _destinationPosition);
    }
    setState(() {
      if (distance > 0.0043) {
        _distanciaRecorrida += distance;
        polylineCoordinates2
            .add(LatLng(_currentPosition.latitude, _currentPosition.longitude));
        registrosGeograficos.add(Registro(_currentPosition.latitude,
            _currentPosition.longitude, DateTime.now().toString()));
      }
      print("$distance la distancia recorrida es 0000: $_distanciaRecorrida");
    });
    //this.bloc.enviarKmRecorridos(_distanciaRecorrida);
  }

  _createPolylines(Position start, Position destination) async {
    polylinePoints = PolylinePoints();
    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      "AIzaSyC7QfiXjbjxcGV3BzUC8pkoWyrP_DW9xlQ", // Google Maps API Key
      PointLatLng(start.latitude, start.longitude),
      PointLatLng(destination.latitude, destination.longitude),
      travelMode: TravelMode.driving,
    );

    if (result.points.isNotEmpty) {
      result.points.forEach((PointLatLng point) {
        polylineCoordinates.add(LatLng(point.latitude, point.longitude));
      });
    }

    PolylineId id = PolylineId('poly');
    Polyline polyline = Polyline(
      polylineId: id,
      color: Colors.red.withOpacity(.4),
      points: polylineCoordinates,
      width: 10,
    );
    polylines[id] = polyline;
  }

  Future empezarRuta() async {
    PolylineId id = PolylineId('pol');
    Polyline polyline = Polyline(
      polylineId: id,
      color: Colors.red,
      points: polylineCoordinates2,
      width: 10,
    );
    polylines[id] = polyline;

    setState(() {
      _navegarRuta = true;
      _rutaEscogida = false;
    });

    _timer = new Timer.periodic(Duration(seconds: 10), (timer) async{
      if (_lastPosition != null) {
        this.avanzarRuta();

        if (proveedor.metaArbol <= (_distanciaRecorrida)) {
          print("igvygbuhgvfctvygbuhgvf");
          var resp = await bloc.anadirArbolUser(
              proveedor.biciusuarioUser.correo, proveedor.metaArbol);
          bloc.arboles.map((object) => object.data.arboles).listen((p) {
            // Escuchamos al stream (que no dará dato a dato el conjunto)
            setState(
                () => arbolesUsuario = p); //Le asignamos el conjunto a ligas
            proveedor.arbolesUsuario = arbolesUsuario;
            for (var i = 0; i < arbolesUsuario.length; i++) {
              if (proveedor.metaArbol < arbolesUsuario[i].precio)
                proveedor.metaArbol = arbolesUsuario[i].precio;
              break;
            }
          });
          if (resp) {
            Alert(
                    context: context,
                    title: ('Listo!'),
                    buttons: [
                      DialogButton(
                        color: Colors.green,
                        child: Text(
                          'Vale',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        width: 120,
                      )
                    ],
                    type: AlertType.success,
                    desc: 'Se ha agregado un árbol a tus árboles por plantar')
                .show();
            this.bloc.obtenerArbolesUser(proveedor.biciusuarioUser.correo);
          }
        }
      } else {
        _lastPosition = _currentPosition;
      }
    });

    mapController.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(_currentPosition.latitude, _currentPosition.longitude),
          zoom: 14.0,
        ),
      ),
    );
  }

  void terminarRuta() {
    _timer.cancel();
    setState(() {
      _navegarRuta = false;
      _rutaEscogida = false;
      _distanciaRecorrida = 0;
    });
  }

  Future enviarRegistroRuta() async {
    bool funciona = await this.bloc.enviarRegistroRuta(registrosGeograficos,
        _distanciaRecorrida, proveedor.biciusuarioUser.correo);
    if (funciona) {
      Alert(
              context: context,
              title: ('Listo!'),
              buttons: [
                DialogButton(
                  color: Colors.green,
                  child: Text(
                    'Gracias',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  width: 120,
                )
              ],
              type: AlertType.success,
              desc: 'Se ha registrado tu ruta')
          .show();
    } else
      print("No tan genial");
  }

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  Widget build(BuildContext context) {
    var myProvider = Provider.of<EstadoGlobal>(context, listen: false);
    proveedor = myProvider;
    _pCarro = myProvider.huellaCarro * _distanciaRecorrida;
    _pMoto = myProvider.huellaMoto * _distanciaRecorrida;
    _pBici = myProvider.huellaBici * _distanciaRecorrida;
    var height = MediaQuery.of(context).size.height;
    var width = MediaQuery.of(context).size.width;
    return Container(
      height: height,
      width: width,
      child: Scaffold(
        key: _scaffoldKey,
        body: Stack(
          children: <Widget>[
            // Map View
            GoogleMap(
              markers: markers != null ? Set<Marker>.from(markers) : null,
              initialCameraPosition: _initialLocation,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              mapType: MapType.normal,
              zoomGesturesEnabled: true,
              zoomControlsEnabled: false,
              polylines: Set<Polyline>.of(polylines.values),
              onMapCreated: (GoogleMapController controller) {
                mapController = controller;
              },
            ),

            // Show the place input fields & button for
            // showing the route
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.all(
                        Radius.circular(20.0),
                      ),
                    ),
                    width: width * 0.9,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5.0, bottom: 15.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _puntoInicioView
                              ? _textField(
                                  label: 'Inicio',
                                  hint: 'Escoge el punto de inicio',
                                  initialValue: _currentAddress,
                                  prefixIcon: Icon(Icons.looks_one),
                                  suffixIcon: IconButton(
                                    icon: Icon(Icons.my_location),
                                    onPressed: () {
                                      startAddressController.text =
                                          _currentAddress;
                                      _startAddress = _currentAddress;
                                    },
                                  ),
                                  controller: startAddressController,
                                  width: width,
                                  locationCallback: (String value) {
                                    setState(() {
                                      _startAddress = value;
                                    });
                                  },
                                  multiplier: 0.8)
                              : Container(),
                          SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _textField(
                                  label: 'Destino',
                                  hint: 'Escoge el punto de destino',
                                  initialValue: '',
                                  prefixIcon: Icon(Icons.location_city),
                                  controller: destinationAddressController,
                                  width: width,
                                  locationCallback: (String value) {
                                    setState(() {
                                      _destinationAddress = value;
                                    });
                                  },
                                  multiplier: 0.6),
                              SizedBox(
                                width: 10,
                              ),
                              ButtonTheme(
                                minWidth: 60,
                                child: RaisedButton(
                                  onPressed: (_startAddress != '' &&
                                          _destinationAddress != '')
                                      ? () async {
                                          setState(() {
                                            if (markers.isNotEmpty)
                                              markers.clear();
                                            if (polylines.isNotEmpty)
                                              polylines.clear();
                                            if (polylineCoordinates.isNotEmpty)
                                              polylineCoordinates.clear();
                                            _placeDistance = "Calculando";
                                            _rutaEscogida = true;
                                          });

                                          FocusScopeNode currentFocus =
                                              FocusScope.of(context);
                                          if (!currentFocus.hasPrimaryFocus) {
                                            currentFocus.unfocus();
                                          }

                                          _calculateDistance()
                                              .then((isCalculated) {
                                            if (isCalculated) {
                                              _scaffoldKey.currentState
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                      'Distancia calculada exitosamente'),
                                                ),
                                              );
                                            } else {
                                              _scaffoldKey.currentState
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                      'Error al calcular la distancia'),
                                                ),
                                              );
                                            }
                                          });
                                        }
                                      : null,
                                  color: Colors.green,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10.0),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(2.0),
                                    child: Text(
                                      'Ir',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16.0,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Show current location button
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: MediaQuery.of(context).size.width,
                  child: Padding(
                    padding:
                        const EdgeInsets.only(top: 10.0, bottom: 8.0, right: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: ClipOval(
                            child: Material(
                              color: Colors.orange[100], // button color
                              child: InkWell(
                                splashColor: Colors.orange, // inkwell color
                                child: SizedBox(
                                  width: 56,
                                  height: 56,
                                  child: Icon(Icons.my_location),
                                ),
                                onTap: () {
                                  mapController.animateCamera(
                                    CameraUpdate.newCameraPosition(
                                      CameraPosition(
                                        target: LatLng(
                                          _currentPosition.latitude,
                                          _currentPosition.longitude,
                                        ),
                                        zoom: 14.0,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        _rutaEscogida
                            ? Container(
                                height: 130,
                                width: MediaQuery.of(context).size.width * 0.95,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(8.0),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    FlatButton(
                                      onPressed: empezarRuta,
                                      child: Container(
                                        height: 50,
                                        width: 100,
                                        decoration: BoxDecoration(
                                            color: Colors.green,
                                            borderRadius:
                                                BorderRadius.circular(30)),
                                        child: Center(
                                          child: Text(
                                            "Empezar",
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyText1
                                                .copyWith(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          " $_placeDistance km",
                                          style: Theme.of(context)
                                              .textTheme
                                              .headline6
                                              .copyWith(
                                                  color: Colors.black,
                                                  fontWeight: FontWeight.bold),
                                        ),
                                        Text("Distancia aproximada"),
                                      ],
                                    ),
                                  ],
                                ),
                              )
                            : Container(),
                        _navegarRuta
                            ? GestureDetector(
                                onDoubleTap: () {
                                  setState(() {
                                    if (containerSize == 130) {
                                      containerSize = 280;
                                    } else {
                                      containerSize = 130;
                                    }
                                  });
                                },
                                child: AnimatedContainer(
                                  padding: EdgeInsets.only(top: 20),
                                  duration: Duration(milliseconds: 200),
                                  height: containerSize,
                                  width:
                                      MediaQuery.of(context).size.width * 0.95,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(8.0),
                                    ),
                                  ),
                                  child: ListView(
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                            "Distancia recorrida: " +
                                                _distanciaRecorrida
                                                    .toStringAsFixed(3) +
                                                "km",
                                            style: Theme.of(context)
                                                .textTheme
                                                .headline6
                                                .copyWith(
                                                    color: Colors.black,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 18),
                                          ),
                                        ],
                                      ),
                                      SizedBox(
                                        height: 20,
                                      ),
                                      containerSize == 280
                                          ? Wrap(
                                              runSpacing: 0,
                                              spacing: 0,
                                              children: [
                                                InfoCardRestantes(
                                                  titulo: "Para próximo árbol",
                                                  dato: myProvider
                                                              .biciusuarioUser ==
                                                          null
                                                      ? myProvider.metaArbol -
                                                          _distanciaRecorrida
                                                      : myProvider.metaArbol -
                                                          (_distanciaRecorrida +
                                                              myProvider
                                                                  .biciusuarioUser
                                                                  .metrosRecorridos),
                                                  unidades: "km",
                                                  icono: Icons.nature,
                                                  color: Colors.green,
                                                ),
                                                InfoCardRestantes(
                                                  titulo:
                                                      "Huella del recorrido",
                                                  dato: _pBici,
                                                  unidades: "ton",
                                                  icono: Icons.fingerprint,
                                                  color: Colors.purple,
                                                ),
                                                InfoCardNumbersNoIcon(
                                                  titulo: "Árboles plantados",
                                                  dato: myProvider
                                                              .arbolesUsuario ==
                                                          null
                                                      ? 0
                                                      : myProvider
                                                          .arbolesUsuario.length
                                                          .toDouble(),
                                                  unidades: "árboles",
                                                  color: Colors.green,
                                                  icono: Icons.nature,
                                                ),
                                                GestureDetector(
                                                  onTap: () {
                                                    setState(() {
                                                      _huellaCarbono = true;
                                                      _navegarRuta = false;
                                                    });
                                                  },
                                                  child: InfoCardNumbersNoIcon(
                                                      titulo:
                                                          "Huella de carbono total",
                                                      dato: myProvider
                                                                  .biciusuarioUser ==
                                                              null
                                                          ? _pBici
                                                          : myProvider
                                                                  .biciusuarioUser
                                                                  .huellaCarbonoAcumulada +
                                                              _pBici,
                                                      unidades: "ton",
                                                      color: Colors.purple,
                                                      icono: Icons.fingerprint),
                                                ),
                                              ],
                                            )
                                          : Container(),
                                      SizedBox(
                                        height: 10,
                                      ),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          FlatButton(
                                            onPressed: () {
                                              enviarRegistroRuta();
                                              markers.clear();
                                              polylines.clear();
                                              polylineCoordinates.clear();
                                              terminarRuta();
                                            },
                                            child: Container(
                                              height: 40,
                                              width: 90,
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                    color: Colors.green),
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  "Terminar",
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyText1
                                                      .copyWith(
                                                          color: Colors.green,
                                                          fontWeight:
                                                              FontWeight.bold),
                                                ),
                                              ),
                                            ),
                                          ),
                                          FlatButton(
                                            onPressed: () {
                                              markers.clear();
                                              polylines.clear();
                                              polylineCoordinates.clear();
                                              terminarRuta();
                                            },
                                            child: Container(
                                              height: 40,
                                              width: 90,
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                    color: Colors.red),
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  "Cancelar",
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyText1
                                                      .copyWith(
                                                          color: Colors.red,
                                                          fontWeight:
                                                              FontWeight.bold),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : Container(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _huellaCarbono == true
                ? GestureDetector(
                    onDoubleTap: () {
                      setState(() {
                        _navegarRuta = true;
                        _huellaCarbono = false;
                      });
                    },
                    child: SafeArea(
                      child: Align(
                        alignment: Alignment.center,
                        child: Container(
                          padding: EdgeInsets.only(
                              left: 20, right: 20, bottom: 20, top: 10),
                          height: MediaQuery.of(context).size.height * 0.5,
                          width: MediaQuery.of(context).size.width * 0.9,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            children: [
                              Text(
                                "Te presentamos datos sobre lo que aportas al ambiente al montar en bici",
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyText1
                                    .copyWith(
                                      color: Colors.black,
                                      fontSize: 12,
                                    ),
                                textAlign: TextAlign.center,
                              ),
                              Container(
                                width: double.infinity,
                                height: 50,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      height: double.infinity,
                                      width: 100,
                                    ),
                                    Expanded(
                                      child: Container(
                                        child: Text(
                                          "Huella de carbono",
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyText1
                                              .copyWith(
                                                color: Colors.black,
                                                fontSize: 13,
                                              ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Container(
                                        child: Text(
                                          "Incremento porcentual",
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyText1
                                              .copyWith(
                                                color: Colors.black,
                                                fontSize: 13,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              HuellaCarbonoCard(_pBici, 0, "assets/bici.png"),
                              HuellaCarbonoCard(
                                  _pCarro,
                                  ((_pCarro / _pBici) * 100),
                                  "assets/carro.png"),
                              HuellaCarbonoCard(_pMoto, (_pMoto / _pBici) * 100,
                                  "assets/moto.png"),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                : Container(),
          ],
        ),
      ),
    );
  }
}

class HuellaCarbonoCard extends StatelessWidget {
  final double huellaCarbono;
  final double porcentaje;
  final String img;
  HuellaCarbonoCard(this.huellaCarbono, this.porcentaje, this.img);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 80,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: double.infinity,
            width: 80,
            padding: EdgeInsets.all(10),
            child: Image.asset(this.img),
          ),
          Expanded(
            child: Container(
              padding: EdgeInsets.only(top: 20, bottom: 30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    huellaCarbono.toStringAsFixed(2) + " g ",
                    style: Theme.of(context).textTheme.headline6.copyWith(
                          color: Colors.black54,
                        ),
                  )
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: EdgeInsets.only(top: 20, bottom: 30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    porcentaje > 100
                        ? "+100%"
                        : "+ " + porcentaje.toStringAsFixed(2) + " %",
                    style: Theme.of(context)
                        .textTheme
                        .headline6
                        .copyWith(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
