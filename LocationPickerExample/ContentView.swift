//
//  ContentView.swift
//  LocationPickerExample
//
//  Created by cano on 2025/06/20.
//

import SwiftUI

struct ContentView: View {
    
    @State private var showPicker: Bool = false
    
    var body: some View {
        NavigationStack {
            List {
                Button("Pick a Location") {
                    showPicker.toggle()
                }
                .locationPicker(isPresented: $showPicker) { coordinates in
                    if let coordinates {
                        print(coordinates)
                    }
                }
                NavigationLink("Map Look Around Simple", destination: MapLookAroundSimpleView())
                
                NavigationLink("Map Look Around", destination: MapLookAroundView())
            }
            .navigationTitle("Location Picker")
        }
    }
}

#Preview {
    ContentView()
}
